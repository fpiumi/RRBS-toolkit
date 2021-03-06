#!/bin/sh
#$ -l mem=10G
#$ -l h_vmem=20G
#
# Copyright (C) 2016 INRA
# 
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
#----------------------------------------------------------------------
#authors :
#---------
#	Piumi Francois (francois.piumi@inra.fr)		software conception and development (engineer in bioinformatics)
#	Jouneau Luc (luc.jouneau@inra.fr)		software conception and development (engineer in bioinformatics)
#	Gasselin Maxime (m.gasselin@hotmail.fr)		software user and data analysis (PhD student in Epigenetics)
#	Perrier Jean-Philippe (jp.perrier@hotmail.fr)	software user and data analysis (PhD student in Epigenetics)
#	Al Adhami Hala (hala_adhami@hotmail.com)	software user and data analysis (postdoctoral researcher in Epigenetics)
#	Jammes Helene (helene.jammes@inra.fr)		software user and data analysis (research group leader in Epigenetics)
#	Kiefer Helene (helene.kiefer@inra.fr)		software user and data analysis (principal invertigator in Epigenetics)
#

if [ "$RRBS_HOME" = "" ]
then
	#Try to find RRBS_HOME according to the way the script is launched
	SCRIPT_DIR=`dirname $0`
else
	#Use RRBS_HOME as defined in environment variable
	SCRIPT_DIR="$RRBS_HOME/Differential_analysis"
fi
. $SCRIPT_DIR/../config.sh


configFile=$1
if [ ! -f "$configFile" ]
then
	tput clear
	echo "file '$configFile' does not exists."
	echo ""
	cat $SCRIPT_DIR/readme.txt
	exit 1
fi

#Force conversion dos -> unix (Cf. http://koenaerts.ca/dos2unix-equivalent)
tmpFile="${configFile}.tmp123"
cat $configFile | tr -d '\015' > $tmpFile
mv $tmpFile $configFile

#Check for mandatory parameyets
title=`grep "^#title" $configFile | tr "[:lower:]" "[:upper:]" | sed 's/^.*\t//'`
if [ "$title" = "" ]
then
	echo "You should provide a value to the 'title' parameter in your configuration file '$configFile'. Exiting."
	exit 1
fi

outputDir=`grep "output_dir" $configFile | sed 's/^#output_dir[ \t]*//'`
if [ "$outputDir" = "" ]
then
	outputDir="."
fi
WORK="$outputDir/tmp"
if [ ! -d "$WORK" ]
then
	mkdir $WORK
fi

PID=$$

logFile="$outputDir/get_methylation_differences.${PID}.log"

statistical_method=`grep "^#stat_method" $configFile | tr "[:lower:]" "[:upper:]" | sed 's/^.*\t//'`
DMR_only=`grep "^#DMC_file" $configFile | wc -l `

if [ $DMR_only -eq 0 -a "$statistical_method" != "" ]
then
	$PYTHON_EXECUTE $SCRIPT_DIR/rename_scaffolds.py 1 $configFile $logFile $WORK $PID
	if [ $? -ne 0 ]
	then
		echo "Step rename_scaffolds.py (1) has failed" >> $logFile
		exit 1
	fi

	if [ "$statistical_method" = "METHYLKIT" ]
	then
		$R_EXECUTE CMD BATCH --no-restore --no-save "--args $configFile $logFile $WORK $PID" $SCRIPT_DIR/get_diff_methylKit.R $WORK/get_diff_methylKit.$PID.Rout
	elif [ "$statistical_method" = "METHYLSIG" ]
	then
		$R_EXECUTE CMD BATCH --no-restore --no-save "--args $configFile $logFile $WORK $PID" $SCRIPT_DIR/get_diff_methylSig.R $WORK/get_diff_methylSig.$PID.Rout
	else
		echo "Unexpected value for 'stat_method' parameter : Recieved '$statistical_method'. Attempted either 'methylSig' or 'methylKit'."
		exit 1
	fi
	if [ $? -ne 0 ]
	then
		echo "Differential analsysis step with '$statistical_method' failed." >> $logFile
		exit 1
	fi

	
	$PYTHON_EXECUTE $SCRIPT_DIR/rename_scaffolds.py 2 $configFile $logFile $WORK $PID
	if [ $? -ne 0 ]
	then
		echo "Step rename_scaffolds.py (2) has failed" >> $logFile
		exit 1
	fi

	$PYTHON_EXECUTE $SCRIPT_DIR/get_bed_from_methylDiff.py $configFile $logFile
	if [ $? -ne 0 ]
	then
		echo "Step get_bed_from_methylKit.py has failed" >> $logFile
		exit 1
	fi
fi

if [ $DMR_only -eq 0 ]
then
	$PYTHON_EXECUTE $SCRIPT_DIR/get_obvious_DMC.py $configFile $logFile
	if [ $? -ne 0 ]
	then
		echo "Step get_obvious_DMC.py has failed" >> $logFile
		exit 1
	fi
fi

if [ $DMR_only -eq 0 -a "$statistical_method" != "" ]
then
	$PYTHON_EXECUTE $SCRIPT_DIR/merge_DMCs.py $configFile $logFile
	if [ $? -ne 0 ]
	then
		echo "Step merge_DMCs.py has failed" >> $logFile
		exit 1
	fi
fi

$PYTHON_EXECUTE $SCRIPT_DIR/get_DMRs.py $configFile $logFile
if [ $? -ne 0 ]
then
	echo "Step get_DMRs.py has failed" >> $logFile
	exit 1
fi

rm -rf $WORK


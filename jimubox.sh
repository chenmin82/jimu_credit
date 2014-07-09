#!/bin/bash

# Color definitions
cyan='\E[36;1m'
green='\E[32;1m'
purple='\E[35;1m'
red='\E[31;1m'
nocol='\E[0m'

CreditAddr="https://www.jimubox.com/CreditAssign/List"
lastCreditIndex=""
lastCreditRate=0
CreditListFile=List
checkCount=0
checkInterval=30

parseCreditList()
{
  #set -x
  linesPerCreditIndex=50
  if [ ! -e $CreditListFile ]; then return; fi
  tmpIndexFile=`mktemp --tmpdir=./`
  grep '<div class="span8 ">' -C $linesPerCreditIndex -m 1 $CreditListFile > $tmpIndexFile
  # No credit index yet, return
  if [ $? -eq 1 ]; then
    echo "No credit available. Please wait..." 
    rm -f $tmpIndexFile
    return; 
  fi

  creditIndex=`cat $tmpIndexFile | grep '<a href="/CreditAssign/Index/' -m 1 | tr '<a href="/CreditAssign/Index/' " " | awk ' { print $1 }'`

  # No update...
  if [ "$lastCreditIndex" == "creditIndex" ] ; then return; fi

  # Extract credit index, rate, days, amount.
  creditLine=`tac $tmpIndexFile | grep '<span class="important">' -m 1`
  creditOrigRate=`cat $tmpIndexFile | grep "^[ \t]*<span class=\"\">" | grep -o "[0-9][0-9]*\.\?[0-9]*"`
  creditRate=`echo $creditLine | tr '<span class="important">' " " | tr "%" " "  | awk ' { print $1 } '`
  creditDays=`tac $tmpIndexFile | grep '<span class="title">' -m 1 | grep -o "[0-9]\+"`
  creditAmount=`cat $tmpIndexFile | grep '<span class="important">' -m 1 | grep -o "[0-9][0-9,]*\.\?[0-9]*" | tail -n 1 | awk ' { sub(",", "", $1); print $1 } '`
  mv $tmpIndexFile Index.$creditIndex
  echo -e "Credit $creditIndex/$creditOrigRate%: \$ $creditAmount/$creditRate%/$creditDays days"
  lastCreditIndex=$creditIndex
  lastCreditRate=$creditRate
  if [ `echo "$lastCreditRate > 12" | bc` -ne 0 ] ; then
    echo "A good credit [$lastCreditRate%] appears with $creditAmount remained. Go go go..."
  fi
  #set +x
}

#set -x
while true
do
  echo -e "$checkCount"
  rm -f $CreditListFile
  wget $CreditAddr -O $CreditListFile -q #2>&1 > /dev/null
  parseCreditList
  checkCount=$(($checkCount+1))
  sleep $checkInterval
done

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
checkCount=1
# check interval:
# 0 - 6   : 30 sec
# 7 - 8   : 20 sec
# 9 - 21  : 10 sec
# 22 - 23 : 15 sec
CheckInterval=(30 30 30 30 30 30 30 20 20 10 10 10 10 10 10 10 10 10 10 10 10 10 15 15)
Threshold=0.85 # rate discount ratio

parseCreditList()
{
  #set -x
  linesPerCreditIndex=50
  if [ ! -e $CreditListFile ]; then return; fi
  tmpIndexFile=`mktemp -p .`
  grep '<div class="span8 ">' -C $linesPerCreditIndex -m 1 $CreditListFile > $tmpIndexFile
  # No credit index yet, return
  if [ $? -eq 1 ]; then
    echo "No credit available. Please wait..." 
    rm -f $tmpIndexFile
    return; 
  fi

  creditIndex=`cat $tmpIndexFile | grep '<a href="/CreditAssign/Index/' -m 1 | tr '<a href="/CreditAssign/Index/' " " | awk ' { print $1 }'`

  # No update...
  # if [ "$lastCreditIndex" == "$creditIndex" ] ; then return; fi

  # Extract credit index, rate, days, amount.
  creditLine=`tac $tmpIndexFile | grep '<span class="important">' -m 1`
  creditOrigRate=`cat $tmpIndexFile | grep "^[ \t]*<span class=\"\">" | grep -o "[0-9][0-9]*\.\?[0-9]*"`
  creditRate=`echo $creditLine | tr '<span class="important">' " " | tr "%" " "  | awk ' { print $1 } '`
  creditDays=`tac $tmpIndexFile | grep '<span class="title">' -m 1 | grep -o "[0-9]\+"`
  creditAmount=`cat $tmpIndexFile | grep '<span class="important">' -m 1 | grep -o "[0-9][0-9,]*\.\?[0-9]*" | tail -n 1 | awk ' { sub(",", "", $1); print $1 } '`
  mv $tmpIndexFile Index.$creditIndex
  echo -e "Credit $creditIndex/$creditOrigRate%: \$ $creditAmount/$creditRate%/$creditDays days"
  if [ `echo "scale=4; $creditRate / $creditOrigRate >= $Threshold" | bc` -ne 0 ] ; then
    # If "mail" available and it's a new credit, send out a mail notification.
    echo "------------------------" > mail.txt
    echo "This credit looks good:" >> mail.txt
    echo "  Rate  : $creditRate% / $creditOrigRate%" >> mail.txt
    echo "  Days  : $creditDays" >> mail.txt
    echo "  Amount: \$ $creditAmount" >> mail.txt
    echo "Good luck!" >> mail.txt
    echo "------------------------" >> mail.txt
    if [ ! "$(which mail)" == "" ] && [ ! "$lastCreditIndex" == "$creditIndex" ] ; then
      mail -s "New credit $creditIndex: $creditRate%" chen.max@qq.com < mail.txt
    fi
    cat mail.txt
    rm -f mail.txt
  fi

  if [ ! "$lastCreditIndex" == "$creditIndex" ]; then rm -f Index.$lastCreditIndex; fi
  lastCreditIndex=$creditIndex
  lastCreditRate=$creditRate
  #set +x
}

#set -x
while true
do
  echo -e "${checkCount}\t                        [ `date '+%x %H:%M:%S'` ]"
  rm -f $CreditListFile
  wget $CreditAddr -O $CreditListFile -q #2>&1 > /dev/null
  parseCreditList
  checkCount=$(($checkCount+1))
  sleep ${CheckInterval[`date '+%H'`]}
done

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
# check interval:
# 0 - 6   : 30 sec
# 7 - 8   : 20 sec
# 9 - 21  : 10 sec
# 22 - 23 : 15 sec
CheckInterval=(30 30 30 30 30 30 30 20 20 10 10 10 10 10 10 10 10 10 10 10 10 10 15 15)
RateThreshold=0.85  # Rate discount ratio (real rate that can be retrieved after re-assigning the credit after holding it for 90 days.)
DaysRTPThreshold=15 # At least returns to pricipal in 15 days.

creditLog=""

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

  # A "good" credit:
  #   1. credit rate is greater than original credit rate, OR
  #   2. days needed to recover the principal is less than $DaysRTPThreshold.
  goodCredit=0
  if [ `echo "$creditRate >= $creditOrigRate" | bc` -ne 0 ]; then
    goodCredit=1
    daysToRTP=0
    rateOf90Days=$creditOrigRate
  else
    daysToRTP=`echo "scale=4; ($creditOrigRate - $creditRate) * $creditDays / $creditOrigRate" | bc`
    if [ $creditDays -gt 120 ]; then        # credit that can be assigned again in the future
      rateOf90Days=`echo "scale=4; (90 - $daysToRTP) * $creditOrigRate / 90" | bc`
    else
      rateOf90Days=$creditRate
    fi
    # rateOf90Days = (90 - $daysToRTP) * $creditOrigRate / 90
    # => $rateOf90Days / $creditOrigRate = (90 - $daysToRTP) / 90
    # => (90 - $daysToRTP) / 90 >= $RateThreshold
    # => $daysToRTP <= 90 - 90 * $RateThreshold = 90 * (1 - $RateThreshold)
    # If $daysToRTP=15, then $RateThreshold <= 5/6
    #if [ `echo "scale=4; ($daysToRTP <= $DaysRTPThreshold) && ($rateOf90Days/$creditOrigRate >= $RateThreshold)" | bc` -ne 0 ] ; then
    if [ `echo "scale=4; ($daysToRTP <= $DaysRTPThreshold) || ($rateOf90Days >= 11)" | bc` -ne 0 ] ; then
      goodCredit=1
    fi
  fi
  echo -e "Credit $creditIndex/$creditOrigRate%: \$ $creditAmount / [$creditRate%/$creditDays days] / [$rateOf90Days%/90 days]"

  if [ $goodCredit -eq 1 ]; then
    # If "mail" available and it's a new credit, send out a mail notification.
    echo "------------------------" > mail.txt
    echo "This credit looks good:" >> mail.txt
    echo "    Rate : $rateOf90Days / $creditRate% / $creditOrigRate%" >> mail.txt
    echo "RTP/Days : $daysToRTP / $creditDays" >> mail.txt
    echo "  Amount : \$ $creditAmount" >> mail.txt
    echo "Good luck!" >> mail.txt
    echo "------------------------" >> mail.txt
    newCredit=0;
    if [ ! "$lastCreditIndex" == "$creditIndex" ]; then newCredit=1; fi
    if [ $newCredit -eq 1 ] ; then
      if [ ! "$(which mail)" == "" ]; then
        mail -s "New credit $creditIndex: $creditRate%" chen.max@qq.com < mail.txt
      fi
      # Update credit log, latest credit in second line
      creditInfo="$creditIndex $creditOrigRate $creditDays $creditAmount $creditRate $rateOf90Days $daysToRTP `date +%T`"
      sed -i -e '1a\' -e "$creditInfo" $creditLog
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
checkCount=1
while true
do
  echo -e "${checkCount}\t                        [ `date '+%x %H:%M:%S'` ]"
  creditLog="credit-`date '+%F'.log`"
  if [ ! -e $creditLog ]; then
    echo "Index OrigRate(%) Days Amount($) Rate(%) RateOf90Days(%) DaysToRTP Time" > $creditLog
  fi
  rm -f $CreditListFile
  wget $CreditAddr -O $CreditListFile -q #2>&1 > /dev/null
  parseCreditList
  checkCount=$(($checkCount+1))
  sleep ${CheckInterval[`date '+%H' | sed 's/^0//g'`]}
done

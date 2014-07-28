#!/bin/bash

# Include fetion utility
. ./fetion.sh

# Color definitions
cyan='\E[36;1m'
green='\E[32;1m'
purple='\E[35;1m'
red='\E[31;1m'
nocol='\E[0m'

CreditAddr="https://www.jimubox.com/CreditAssign"
LogFile=jimu.log
CreditListFile=List
# check interval:
# 0 - 6   : 30 sec
# 7 - 8   : 20 sec
# 9 - 21  : 10 sec
# 22 - 23 : 15 sec
CheckInterval=(30 30 30 30 30 30 30 20 20 10 10 10 10 10 10 10 10 10 10 10 10 10 15 15)
RateThreshold=0.85  # Rate discount ratio (real rate that can be retrieved after re-assigning the credit after holding it for 90 days.)
DaysRTPThreshold=15 # At least returns to pricipal in 15 days.
CreditIndexInfoList=""
creditLog=""
DEBUG=0
FETION_NOTIFY=0
FETION_CFG=fetion.cfg
OS_RELEASE=`cat /etc/issue | head -n 1 | cut -d' ' -f1`

parseArgs() {
  echo "Args: $@"
  while [ $# -gt 0 ]
  do
    case "$1" in
      "-d")
	DEBUG=1
	rm -f debug*.log
	#set -x
	;;
      "--fetion")
        if [ -e $FETION_CFG ]; then
	  FETION_NOTIFY=1;
	else
	  echo "No configuration file $FETION_CFG exists. Disable --fetion option."
	fi
        ;;
    esac
    shift
  done
}

format() {
  echo "$1" | awk '
    BEGIN {
      logFormat="%-6s %10s %12s %8s %15s %9s %5s %10s\n"
    }
    { printf logFormat, $1, $2, $3, $4, $5, $6, $7, $8 }
  '
}

parseCreditList()
{
  #set -x
  linesPerCreditIndex=50
  if [ ! -e $CreditListFile ]; then return; fi
  if [ `cat $CreditListFile | wc -c` -eq 0 ]; then return; fi
  tmpIndexFile=`mktemp -p .`
  grep '<div class="span8 ">' -C $linesPerCreditIndex -m 1 $CreditListFile > $tmpIndexFile
  # No credit index yet, return
  if [ $? -eq 1 ]; then
    echo "No credit available. Please wait..."
    rm -f $tmpIndexFile
    CreditIndexInfoList=""
    return
  fi

  creditIndex=`cat $tmpIndexFile | grep '<a href="/CreditAssign/Index/' -m 1 | tr '<a href="/CreditAssign/Index/' " " | awk ' { print $1 }'`

  # whether it'a a new credit?
  newCredit=1
  for indexInfo in $CreditIndexInfoList; do
    index=`echo "$indexInfo" | awk -F ';' ' { print $1 } '`
    if [ $index -eq $creditIndex ]; then
      newCredit=0
      creditOrigRate=`echo "$indexInfo" | awk -F ';' ' { print $2 } '`
      creditAmount=`echo "$indexInfo" | awk -F ';' ' { print $3 } '`
      creditRate=`echo "$indexInfo" | awk -F ';' ' { print $4 } '`
      creditDays=`echo "$indexInfo" | awk -F ';' ' { print $5 } '`
      rateOf90Days=`echo "$indexInfo" | awk -F ';' ' { print $6 } '`
      break
    fi
  done

  # No update...
#  if [ "$lastCreditIndex" == "$creditIndex" ] ; then
  if [ $newCredit -eq 0 ] ; then
    creditAmount=`cat $tmpIndexFile | grep '<span class="important">' -m 1 | grep -o "[0-9][0-9,]*\.\?[0-9]*" | tail -n 1 | awk ' { sub(",", "", $1); print $1 } '`
    echo -e "Credit $creditIndex/$creditOrigRate%: \$ $creditAmount / [$creditRate%/$creditDays days] / [$rateOf90Days%/90 days]"
    rm -f $tmpIndexFile
    return
  fi

  IndexFile=Index.$creditIndex
  wget --timeout=10 --tries=10 $CreditAddr/Index/$creditIndex -O $IndexFile -a $LogFile #2>&1 > /dev/null

  # Extract credit value, rate, days, amount.
  #creditLine=`tac $tmpIndexFile | grep '<span class="important">' -m 1`
  #creditOrigRate=`cat $tmpIndexFile | grep "^[ \t]*<span class=\"\">" | grep -o "[0-9][0-9]*\.\?[0-9]*"`
  #creditRate=`echo $creditLine | tr '<span class="important">' " " | tr "%" " "  | awk ' { print $1 } '`
  #creditDays=`tac $tmpIndexFile | grep '<span class="title">' -m 1 | grep -o "[0-9]\+"`
  #creditAmount=`cat $tmpIndexFile | grep '<span class="important">' -m 1 | grep -o "[0-9][0-9,]*\.\?[0-9]*" | tail -n 1 | awk ' { sub(",", "", $1); print $1 } '`
  tmpInfo=`grep "^[ \t]*[0-9][0-9,]*\.\?[0-9]*" $IndexFile | awk ' {sub(",", "", $1); print $1 } '`
  creditValue=`echo "$tmpInfo" | sed -n '1p'`
  creditFV=`echo "$tmpInfo" | sed -n '2p'`
  creditPrice=`echo "$tmpInfo" | sed -n '3p'`
  tmpInfo=`grep '<span class="">' $IndexFile`
  creditOrigRate=`echo "$tmpInfo" | tail -n 1 | grep -o "[0-9][0-9,]*\.\?[0-9]*"`
  creditDays=`echo "$tmpInfo" | head -n 1 | grep -o "[0-9][0-9,]*\.\?[0-9]*"`
  tmpInfo=`grep '<span class="important">' $IndexFile | grep -o "[0-9][0-9,]*\.\?[0-9]*" | awk ' {sub(",", "", $1); print $1 } '`
  creditAmount=`echo "$tmpInfo" | sed -n '1p'`
  creditRate=`echo "$tmpInfo" | sed -n '2p'`
  rm -f $tmpIndexFile $IndexFile

  # A "good" credit:
  #   1. credit rate is greater than original credit rate, OR
  #   2. days needed to recover the principal is less than $DaysRTPThreshold.
  goodCredit=0
  rateOf90Days=0.00
  if [ ${creditValue%\.[0-9]*} -gt 500 ]; then
    if [ `echo "$creditRate >= $creditOrigRate" | bc` -ne 0 ]; then
      goodCredit=1
      daysToRTP=0
      if [ $creditDays -gt 120 ]; then
        rateOf90Days=`echo "scale=2; $creditOrigRate * $creditValue / $creditPrice + ($creditFV - $creditPrice) * 36500 / ($creditPrice * 90)" | bc`
      else
        rateOf90Days=$creditRate
      fi
    else
      daysToRTP=`echo "scale=2; ($creditPrice - $creditFV) / ($creditOrigRate * $creditValue / 36500) " | bc`
      if [ $creditDays -gt 120 ]; then        # credit that can be assigned again in the future
        rateOf90Days=`echo "scale=2; (90 - $daysToRTP) * $creditOrigRate * $creditValue / (90 * $creditPrice)" | bc`
      else
        rateOf90Days=$creditRate
      fi
      #if [ `echo "scale=4; ($daysToRTP <= $DaysRTPThreshold) && ($rateOf90Days/$creditOrigRate >= $RateThreshold)" | bc` -ne 0 ] ; then
      if [ `echo "scale=4; ($daysToRTP <= $DaysRTPThreshold) || ($rateOf90Days >= 11)" | bc` -ne 0 ] ; then
        goodCredit=1
      fi
    fi
  fi
  echo -e "Credit $creditIndex/$creditOrigRate%: \$ $creditAmount / [$creditRate%/$creditDays days] / [$rateOf90Days%/90 days]"
  creditIndexInfo="$creditIndex;$creditOrigRate;$creditAmount;$creditRate;$creditDays;$rateOf90Days"
  CreditIndexInfoList="$creditIndexInfo $CreditIndexInfoList"

  if [ $DEBUG -eq 1 ] ; then
    if [ ! -e debug_credits.log ]; then
      echo "# All the credits parsed are listed below:" > debug_credits.log
      echo "$creditIndexInfo" >> debug_credits.log
    else
      sed -i -e '1a\' -e "$creditIndexInfo" debug_credits.log
    fi
  fi

  if [ $goodCredit -eq 1 ]; then
    # If "mail" available and it's a new credit, send out a mail notification.
    echo "This credit looks good:" > mail.txt
    echo "    Rate : $rateOf90Days% / $creditRate% / $creditOrigRate%" >> mail.txt
    echo "RTP/Days : $daysToRTP / $creditDays" >> mail.txt
    echo "  Amount : \$ $creditAmount" >> mail.txt
    echo "Val/FV/P : \$ $creditValue / $creditFV / $creditPrice" >> mail.txt
    echo "Good luck!" >> mail.txt
    if [ $newCredit -eq 1 ] ; then
      if [ ! "$(which mail)" == "" ]; then
	if [ "$OS_RELEASE" == "Ubuntu" ]; then
	  mail -s "New credit $creditIndex: $creditRate%" chen.max@139.com < mail.txt
	elif ["$OS_RELEASE" == "CentOS" ]; then
	  mail -s "New credit $creditIndex: $creditRate%" chen.max@qq.com -- -f chenmin82@gmail.com < mail.txt
	fi
      fi
      if [ ${FETION_NOTIFY} -eq 1 ]; then
	# NOTICE: '%' is NOT allowed in fetion message.
	local msg="$creditIndex Rate: $rateOf90Days/$creditRate/$creditOrigRate; RTP/Days: $daysToRTP/$creditDays; Val/FV/P: $creditValue/$creditFV/$creditPrice."
	local msg_dbg="[`date +%T`] $msg"

	send_msg "$msg_dbg"
	if [ -e ${TempDir}/send_msg.result ]; then
	  msg_dbg="$msg_dbg -> `cat ${TempDir}/send_msg.result`"
	  rm -f ${TempDir}/send_msg.result
	fi

	if [ $DEBUG -eq 1 ] ; then
	  if [ ! -e debug_fetion.log ]; then
	    echo "# All the messages sent by Fetion are listed below:" > debug_fetion.log
	    echo "$msg_dbg" >> debug_fetion.log
	  else
	    sed -i -e '1a\' -e "$msg_dbg" debug_fetion.log
	  fi
	fi
      fi
      # Update credit log, latest credit in second line
      creditInfo=$(format "$creditIndex $creditAmount $creditOrigRate $creditRate $rateOf90Days $daysToRTP $creditDays `date +%T`")
      sed -i -e '1a\' -e "$creditInfo" $creditLog
    fi
    echo "------------------------"
    cat mail.txt
    echo "------------------------"
    rm -f mail.txt
  fi
}

#set -x
checkCount=1
parseArgs "$@"

if [ ${FETION_NOTIFY} -eq 1 ]; then
  read_cfg < $FETION_CFG
  login
  send_msg "JIMU credit parser started."
  keep_alive &
fi

while true
do
  echo -e "${checkCount}\t                        [ `date '+%x %H:%M:%S'` ]"
  creditLog="credit-`date '+%F'`.log"
  if [ ! -e $creditLog ]; then
    format "Index Amount($) OrigRate(%) Rate(%) RateOf90Days(%) DaysToRTP Days Time" > $creditLog
  fi
  rm -f $CreditListFile
  wget --timeout=10 --tries=10 $CreditAddr/List -O $CreditListFile -o $LogFile #2>&1 > /dev/null
  parseCreditList
  checkCount=$(($checkCount+1))
  sleep ${CheckInterval[`date '+%H' | sed 's/^0//g'`]}
done

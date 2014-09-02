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
#Options="status=1&guarantee=&order=rate&category="
#Options="status=1&guarantee=&order=rate&order2=none&category="
Options="status=1&guarantee=&category=&rate=0&days=0"
#DiyaOption="status=1&guarantee=&order=rate&category=3"
LogFile=jimu.log
# check interval:
# HOUR  ---->  0        3        6        9        12       15       18       21    23
CheckInterval=(20 30 30 30 30 30 20 15 8  8  8  10 10 10 10 5  5  5  5  10 10 10 15 15)
RateThreshold=0.85  # Rate discount ratio (real rate that can be retrieved after re-assigning the credit after holding it for 90 days.)
DaysRTPThreshold=15 # At least returns to pricipal in 15 days.
CreditIndexInfoList=""
creditLog=""
DEBUG=0
FETION_NOTIFY=0
MAIL_NOTIFY=0
JIMU_ROBBER=1
JM_robber_credit=../tmp/minJimuTmp/.credits
FETION_CFG=fetion.cfg
OS_RELEASE=`cat /etc/issue | head -n 1 | cut -d' ' -f1`
JM_ProjectFilter=

updateFilter() {
  set +x
  JM_ProjectFilter=""
  while read -r line
  do
#    line=${line##+[ \t]}
#    line=${line%%+[ \t]}
    #echo $line
    case "$line" in
      \#*)
        # ignore commets
        #echo "comment line: $line"
        ;;
      [0-9]*)
        JM_ProjectFilter="$JM_ProjectFilter $line"
        ;;
      *)
        #echo "No matching for: $line"
        ;;
    esac
  done
  JM_ProjectFilter="$JM_ProjectFilter "
  echo "JM_ProjectFilter=[$JM_ProjectFilter]"
}

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

parseCredit() {
  # whether it'a a new credit?
  newCredit=1
  for indexInfo in $CreditIndexInfoList; do
    index=`echo "$indexInfo" | awk -F ';' ' { print $1 } '`
    if [ $index -eq $creditIndex ]; then
      newCredit=0
      creditOrigRate=`echo "$indexInfo" | awk -F ';' ' { print $2 } '`
      creditValue=`echo "$indexInfo" | awk -F ';' ' { print $3 } '`
      creditRate=`echo "$indexInfo" | awk -F ';' ' { print $4 } '`
      creditDays=`echo "$indexInfo" | awk -F ';' ' { print $5 } '`
      rateOf90Days=`echo "$indexInfo" | awk -F ';' ' { print $6 } '`
      creditDiscountRate=`echo "$indexInfo" | awk -F ';' ' { print $7 } '`
      return 0
    fi
  done

  IndexFile=Index.$creditIndex
  wget --timeout=10 --tries=10 $CreditAddr/Index/$creditIndex -O $IndexFile -a $LogFile #2>&1 > /dev/null

  grep -q "<title>404" $IndexFile
  if [ $? -eq 0 ]; then
  # credit not exist
    echo "Credit $creditIndex not exist."
    rm -f $IndexFile
    return 1
  fi

  # No update...
#  if [ "$lastCreditIndex" == "$creditIndex" ] ; then
  if [ $newCredit -eq 0 ] ; then
    local creditUsed=`cat $tmpIndexFile | grep 'project-current-money' | grep -o "[0-9][0-9,]*\.\?[0-9]*"  | sed 's/,//g'`
    creditAmount=`echo "$creditValue-$creditUsed" | bc`
    echo -e "Credit $creditIndex/$creditOrigRate%+$creditDiscountRate%: \$ $creditAmount / [$creditRate%/$creditDays days] / [$rateOf90Days%/90 days]"
    rm -f $tmpIndexFile
    return 0
  fi

  # Extract credit value, rate, days, amount.
  tmpInfo=`grep "^[ \t]*[0-9][0-9,]*\.\?[0-9]*" $IndexFile | awk ' {sub(",", "", $1); print $1 } '`
  creditValue=`echo "$tmpInfo" | sed -n '1p'`
  creditFV=`echo "$tmpInfo" | sed -n '2p'`
  creditPrice=`echo "$tmpInfo" | sed -n '3p'`
  creditDiscountRate=`echo "$tmpInfo" | sed -n '4p'`
  tmpInfo=`grep 'class="">' $IndexFile`
  creditDays=`echo "$tmpInfo" | sed -n '4p' | grep -o "[0-9][0-9,]*\.\?[0-9]*"`
  creditOrigRate=`grep  "^[ \t]\+<span>" $IndexFile | sed -n '1p' | grep -o "[0-9][0-9,]*\.\?[0-9]*"`
  tmpInfo=`grep 'class="important">' $IndexFile | grep -o "[0-9][0-9,]*\.\?[0-9]*" | awk ' {sub(",", "", $1); print $1 } '`
  creditAmount=`echo "$tmpInfo" | sed -n '1p'`
  projectId=`grep "/Project/Index" $IndexFile | sed '1{s/^.*[ \t]//g;s/-.*$//g}'`
  rm -f $tmpIndexFile $IndexFile

  # Index has been already assigned.
  [ "$creditOrigRate" == "" ] && return 0

  # A "good" credit:
  #   1. credit rate is greater than original credit rate, OR
  #   2. days needed to recover the principal is less than $DaysRTPThreshold.
  goodCredit=0
  filtered=0
  creditRate=`echo "scale=2; ($creditFV-$creditPrice)*36500/$creditPrice/$creditDays+$creditOrigRate*$creditValue/$creditPrice" | bc`
  rateOf90Days=`echo "scale=2; ($creditFV-$creditPrice)*36500/$creditPrice/90+$creditOrigRate*$creditValue/$creditPrice" | bc`

  echo ${JM_ProjectFilter} | grep " ${projectId} " -q
  [ $? -eq 0 ] && filtered=1
  if [ $filtered -eq 1 ]; then
    goodCredit=0
  elif [ `echo "$creditOrigRate >= 14 || $creditRate >=14.5" | bc` -ne 0 ]; then
    goodCredit=1
  fi
  echo -e "Credit $creditIndex/$creditOrigRate%+$creditDiscountRate%: \$ $creditAmount / [$creditRate%/$creditDays days] / [$rateOf90Days%/90 days]"
  creditIndexInfo="$creditIndex;$creditOrigRate;$creditValue;$creditRate;$creditDays;$rateOf90Days;$creditDiscountRate"
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
    echo "Dis/Days : $creditDiscountRate / $creditDays" >> mail.txt
    echo "  Amount : \$ $creditAmount" >> mail.txt
    echo "Val/FV/P : \$ $creditValue / $creditFV / $creditPrice" >> mail.txt
    echo "Good luck!" >> mail.txt
    if [ $newCredit -eq 1 ] ; then
      # Notify the jimu robber there is a new good credit
      if [ $JIMU_ROBBER -eq 1 ]; then
        echo $creditIndex > ${JM_robber_credit}
      fi
      if [ ${FETION_NOTIFY} -eq 1 ]; then
        # NOTICE: '%' is NOT allowed in fetion message.
        local msg="[$creditAmount] Rate: $rateOf90Days/$creditRate/$creditOrigRate; Dis/Days: $creditDiscountRate/$creditDays; Val/FV/P: $creditValue/$creditFV/$creditPrice. [$creditIndex]"
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
      if [ ! "$(which mail)" == "" -a ${MAIL_NOTIFY} -eq 1 ]; then
        if [ "$OS_RELEASE" == "Ubuntu" ]; then
          mail -s "New credit $creditIndex: $creditRate%" chen.max@139.com < mail.txt
        elif [ "$OS_RELEASE" == "CentOS" ]; then
          mail -s "New credit $creditIndex: $creditRate%" chen.max@qq.com -- -f chenmin82@gmail.com < mail.txt
        fi
      fi
      # Update credit log, latest credit in second line
      creditInfo=$(format "$creditIndex $creditValue $creditOrigRate $creditRate $rateOf90Days $creditDiscountRate $creditDays `date +%T`")
      sed -i -e '1a\' -e "$creditInfo" $creditLog
    fi
    echo "------------------------"
    cat mail.txt
    echo "------------------------"
    rm -f mail.txt
  fi
  return 0
}

parseFirstCredit()
{
  local Opitons1st="status=1&guarantee=&category=&rate=0&days=0"
  local CreditListFile=List1st
  local linesPerCreditIndex=40
  local creditSepLineKey="project-card"

  wget --timeout=10 --tries=10 "$CreditAddr/List?${Options1st}" -O $CreditListFile -o $LogFile #2>&1 > /dev/null

  if [ ! -e $CreditListFile ]; then return 1; fi
  if [ `cat $CreditListFile | wc -c` -eq 0 ]; then return 1; fi
  tmpIndexFile=`mktemp -p .`
  grep "$creditSepLineKey" -A $linesPerCreditIndex -m 1 $CreditListFile > $tmpIndexFile
  # No credit index yet, return
  if [ $? -eq 1 ]; then
    echo "No credit available. Please wait..."
    rm -f $tmpIndexFile $CreditListFile
    CreditIndexInfoList=""
    return 1
  fi

  creditIndex=`cat $tmpIndexFile | grep "/CreditAssign/Index/[0-9]\+" -o  -m 1 | cut -d'/' -f4`
  parseCredit $creditIndex
  rm -f $tmpIndexFile $CreditListFile
  return 0
}

isPageLinkAvailable() {
  local CreditListFile=$1
  local pageNo=$2

  if [ ! -e $CreditListFile ]; then return 1; fi

  # whether next page availabe
  grep -q "&page=${pageNo}&" $CreditListFile
  if [ $? -eq 0 ] ; then
    echo "Page $pageNo available."
    return 0
  else
    echo "Page $pageNo NOT available."
    return 1
  fi

}

parseCreditListInCurrPage()
{
#set -x
  local CreditListFile=$1
  local currentPage=$2
  local linesPerCreditIndex=50
  local totalCreditsInCurrPage=0
  local creditSepLineKey="project-card"
  totalCreditsInCurrPage=`grep $creditSepLineKey $CreditListFile | wc -l`
  if [ $currentPage -eq 1 ] && [ $totalCreditsInCurrPage -eq 0 ] ; then
    echo "No credit >=12% available. Please wait..."
    return
  fi

  echo "There are $totalCreditsInCurrPage credits in Page $currentPage."
  # for ((i=0; i<$totalCreditsInCurrPage; i++))
  for i in `seq $totalCreditsInCurrPage`
  do
    # get (i)th credit in current page
    echo "Get ($i)th credit in Page $currentPage."
    tmpIndexFile=`mktemp -p .`
    grep $creditSepLineKey -C $linesPerCreditIndex -m $i $CreditListFile | tail -n $(($linesPerCreditIndex+1)) > $tmpIndexFile
    # No credit index yet, return
    creditIndex=`cat $tmpIndexFile | grep "/CreditAssign/Index/[0-9]\+" -o -m 1 | cut -d'/' -f4`
    parseCredit $creditIndex
    rm -f $tmpIndexFile
  done
}

parseCredit12_14() {
  set -x
  local Options12="status=1&guarantee=&category=&rate=3&days=0"
  local CreditListFile=List12
  local linesPerCreditIndex=40
  local creditSepLineKey="project-card"
  local maxPages=1
  local currentPage=1

  while [ 1 ]; do
    rm -f $CreditListFile
    wget --timeout=10 --tries=10 "$CreditAddr/List?${Options12}&page=${currentPage}" -O $CreditListFile -o $LogFile
    parseCreditListInCurrPage ${CreditListFile} ${currentPage}
    isPageLinkAvailable ${CreditListFile} $((currentPage+1))
    if [ $? -eq 0 ]; then
      currentPage=$(($currentPage+1))
    else
      break
    fi
    if [ $maxPages -gt 0 -a $currentPage -gt $maxPages ]; then break; fi
  done
  rm -f ${CreditListFile}
  set +x
}

checkCount=1
parseArgs "$@"

if [ ${FETION_NOTIFY} -eq 1 ]; then
  read_cfg < $FETION_CFG
  login
  send_msg "JIMU credit parser started."
  keep_alive &
fi
#if [ ${JIMU_ROBBER} -eq 1 ]; then
#  jimu_login
#  jimu_robber &
#fi

while true
do
  set +x
  updateFilter < filter.cfg
  echo -e "${checkCount}\t                        [ `date '+%x %H:%M:%S'` ]"
  creditLog="credit-`date '+%F'`.log"
  set -x
  if [ ! -e $creditLog ]; then
    format "Index Amount($) OrigRate(%) Rate(%) RateOf90Days(%) DisctRate Days Time" > $creditLog
    creditIndex=""
  fi
  rm -f $CreditListFile
  parseFirstCredit
  parseCredit12_14
  checkCount=$(($checkCount+1))
  sleep 3 #${CheckInterval[`date '+%H' | sed 's/^0//g'`]}
done

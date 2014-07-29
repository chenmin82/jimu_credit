#!/bin/bash
#Convert Python Fetion To Shell @2012

user='' # User mobile phone number
password='' # Login password of $user
KEEP_ALIVE=2400000 # Keep alive interval in ms (default 40 minutes)
code=""
url_base='http://f.10086.cn/im5'
url_init='http://f.10086.cn/im5/login/login.action'
url_login='http://f.10086.cn/im5/login/loginHtml5.action' #'http://f.10086.cn/im/login/inputpasssubmit1.action'
url_logout='http://f.10086.cn/im5/login/login.action?type=logout'
url_msg='http://f.10086.cn/im5/chat/sendNewGroupShortMsg.action'
TempDir='./minFetionTmp'
Uagent='Mozilla/5.0'
LOGIN="$TempDir/.fetion.login"
SMS_LOG="$TempDir/.sms.log"
t_login_local=0 # local login time in ms
t_login=0       # login time in ms from server
t_last_sms=0    # time last sms sent out.

read_cfg() {
  while read -r value
  do
    value=${value##^[[:space:]]+}
    value=${value%%[[:space:]]+}
    case "$value" in
      user=*)
	user=${value##user=};;
      password=*)
	password=${value##password=};;
      keepalive=*)
        KEEP_ALIVE=${value##keepalive=};;
      *);;
    esac
  done
  # echo "user=$user, password=$password, keepalive=$KEEP_ALIVE"
}

throw() {
  echo "$*" >&2
  exit 1
}

get_now() {
  local now_sec=`date +%s`
  local now_ns=`date +%N | sed 's/^0\+//g'`  # Removing leading 0.
  local now_t=$(($now_sec*1000+$now_ns/1000000))
  echo "$(($now_t-$t_login_local+$t_login))"
}

sms_log() {
  local log="`get_now` $1"
  [ -e ${SMS_LOG} ] || echo "# All the logs sent by fetion are listed here:" > ${SMS_LOG}
  sed -i -e '1a\' -e "$log" ${SMS_LOG} 
}

get_last_sms_time() {
  echo `sed -n '2p' ${SMS_LOG} | cut -d' ' -f1`
}

make_argt() {
  echo "t=`get_now`"
}

parse_captcha_code() {
  read -p "Please enter the CaptchaCode: " code
  echo "The code is: [$code]"
}

tokenize() {
  local ESCAPE='(\\[^u[:cntrl:]]|\\u[0-9a-fA-F]{4})'
  local CHAR='[^[:cntrl:]"\\]'
  local STRING="\"$CHAR*($ESCAPE$CHAR*)*\""
  local NUMBER='-(0|[1-9][0-9]*)([.][0-9]*)([eE][+-][0-9]*)'
  local KEYWORD='null|false|true'
  local SPACE='[[:space:]]+'
  egrep -ao "$STRING|$NUMBER|$KEYWORD|$SPACE|." |
  egrep -v "^$SPACE$" # eat whitespace
}


parse_array() {
  local index=0
  local ary=''
  read -r token
  case "$token" in
    ']') ;;
    *)
      while :
      do
        parse_value "$1" "$index"
	let index=$index+1
	ary="$ary""$value"
	read -r token
	case "$token" in
	  ']') break ;;
	  ',') ary="$ary," ;;
	  *) throw "EXPECTED , or ] GOT ${token:-EOF}" ;;
	esac
	read -r token
      done
    ;;
  esac
  value=`printf '[%s]' "$ary"`
}


parse_object() {
  local key
  local obj=''
  read -r token
  case "$token" in
    '}') ;;
    *)
      while :
      do
	case "$token" in
	  '"'*'"') key=$token ;;
	  *) throw "EXPECTED string GOT ${token:-EOF}" ;;
	esac
	read -r token
	case "$token" in
	  ':') ;;
	  *) throw "EXPECTED : GOT ${token:-EOF}" ;;
	esac
	read -r token
	parse_value "$1" "$key"
	obj="$obj$key:$value"
	read -r token
	case "$token" in
	  '}') break ;;
	  ',') obj="$obj," ;;
	  *) throw "EXPECTED , or } GOT ${token:-EOF}" ;;
	esac
	read -r token
      done
      ;;
  esac
  value=`printf '{%s}' "$obj"`
}


parse_value() {
  local jpath="${1:+$1,}$2"
  case "$token" in
    '{') parse_object "$jpath" ;;
    '[') parse_array "$jpath" ;;
# At this point, the only valid single-character tokens are digits.
    ''|[^0-9]) throw "EXPECTED value GOT ${token:-EOF}" ;;
    *) value=$token ;;
  esac
  printf "[%s]\t%s\n" "$jpath" "$value"
}


parse() {
  read -r token
  parse_value
  read -r token
  case "$token" in
    '') ;;
    *) throw "EXPECTED EOF GOT $token" ;;
  esac
}

login() {
  echo "Login: `date`"
  if [ -d "$TempDir" ]; then
    rm -rf ${TempDir}/*
    #mkdir -p "$TempDir"
  else
    mkdir -p "$TempDir"
  fi

  wget -q -P ${TempDir} --save-cookies=${TempDir}/cookie -U ${Uagent} --keep-session-cookies ${url_init}

  js_loader=`grep -o "js/loader.js?t=[0-9]*" ${TempDir}/login.action`
  t_login=${js_loader##[^=]*=}
  t_login_local=$((`date +%s`*1000+`date +%N | sed 's/^0\+//g'`/1000000))
# echo "t_login=$t_login, t_login_local=$t_login_local"
  wget -q -P ${TempDir} --load-cookies=${TempDir}/cookie -U ${Uagent} --keep-session-cookies ${url_base}/${js_loader} -O ${TempDir}/loader.js

  tmp=`get_now`
  arg_t="t=$tmp"
  wget -q -P ${TempDir} --load-cookies=${TempDir}/cookie -U ${Uagent} --keep-session-cookies "${url_base}/systemimage/verifycode${tmp}.png?tp=im5&${arg_t}" -O ${TempDir}/code1.png

#  tmp=`get_now`
#  arg_t="t=$tmp"
#  wget -q -P ${TempDir} --load-cookies=${TempDir}/cookie -U ${Uagent} --keep-session-cookies "${url_base}/systemimage/verifycode${tmp}.png?tp=im5&${arg_t}" -O ${TempDir}/code2.png

  parse_captcha_code

# Special notice: we need to update the cookie here.
  wget -q -P ${TempDir} --load-cookies=${TempDir}/cookie -U ${Uagent} --keep-session-cookies --save-cookies=${TempDir}/cookie --post-data "m=${user}&pass=${password}&captchaCode=${code}&checkCodeKey=null" "${url_login}?`make_argt`" -O ${TempDir}/loginHtml5.action

  #cat ${TempDir}/loginHtml5.action
  #cp ${TempDir}/loginHtml5.action ${TempDir}/login.action
  #echo ""
:
#arg_t=`tokenize < ${TempDir}/loginHtml5.action | parse | grep -e '^\[\"headurl\"]'| awk '{print $2}'|sed 's/"//g' | grep -Eo 't=\w+'`
  headurl=`tokenize < ${TempDir}/loginHtml5.action | parse | grep -e '^\[\"headurl\"]'| awk '{print $2}'| sed 's/"//g'`
  #echo ${headurl}
  #echo ${arg_t}
  idUser=`tokenize < ${TempDir}/loginHtml5.action | parse | grep -e '^\[\"idUser\"]'| awk '{print $2}'|sed 's/"//g'`
  #echo ${idUser}

  wget -q -P ${TempDir} --load-cookies=${TempDir}/cookie -U ${Uagent} --keep-session-cookies  --referer=${url_init} ${headurl}

  [ -e $LOGIN ] && rm -f $LOGIN
  touch $LOGIN
  echo "# All the logs sent by fetion are listed here:" > ${SMS_LOG}
}

send_msg() {
  local last=$t_last_sms
  if [ $# -eq 0 ] ; then return; fi
  local msg=$1
#  t_last_sms=`get_now`
  arg_t="`make_argt`"

  wget -q -P ${TempDir} --load-cookies=${TempDir}/cookie -U ${Uagent} --keep-session-cookies --post-data "msg=${msg}&touserid=%2c${idUser}" --referer=${url_init} ${url_msg}?${arg_t} -O ${TempDir}/send_msg.action

  tokenize < ${TempDir}/send_msg.action | parse | grep -e '^\[\"info\"]'|awk '{print $2}'| sed 's/"//g' > ${TempDir}/send_msg.result

  sms_log "[`date`] [$msg] -> `cat ${TempDir}/send_msg.result`"
  echo "$t_last_sms|$last [`date`] [$msg] -> `cat ${TempDir}/send_msg.result`" >> debug_sms.log
}

# Keep seesion alive till logout.
keep_alive() {
  while [ -e $LOGIN ]; do
    url_keepalive="${url_base}/box/alllist.action"
    wget -q -P ${TempDir} --load-cookies=${TempDir}/cookie -U ${Uagent} --keep-session-cookies --post-data "" ${url_keepalive}?`make_argt` -O ${TempDir}/keep_alive.action
    echo "Keep alive: `date`"

    # It seems if we doesn't send any sms in longer than 40minutes, it won't send sms anymore before we login again.
    # So here we will send out a sms to keep the sever "alive".
    local tmp=`get_now`
    local last=`get_last_sms_time`
    if [ $tmp -ge $((last+${KEEP_ALIVE})) ]; then
      send_msg "Send keep-alive msg after $(((tmp-last)/1000)) seconds."
    fi
    sleep 15
  done
  # In case we terminate fetion.sh unexpected by CTRL+C
  if [ -e ${TempDir}/cookie ]; then fetion_logout; fi
  #exit 0
}

fetion_logout() {
  rm -rf $LOGIN
  #wget -q -P ${TempDir} --load-cookies=${TempDir}/cookie -U ${Uagent} --keep-session-cookies ${url_logout}"&"${arg_t}
  wget -q -P ${TempDir} --load-cookies=${TempDir}/cookie -U ${Uagent} ${url_logout}"&"${arg_t} -O ${TempDir}/logout.action
  echo "Logout: `date`"
  rm -rf ${Tempdir}/cookie
#rm -rf ${TempDir}
}


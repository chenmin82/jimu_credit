#!/bin/bash
#Convert Python Fetion To Shell @2012

user='' # User mobile phone number
password='' # Login password of $user
code=""
url_base='http://f.10086.cn/im5'
url_init='http://f.10086.cn/im5/login/login.action'
url_login='http://f.10086.cn/im5/login/loginHtml5.action' #'http://f.10086.cn/im/login/inputpasssubmit1.action'
url_logout='http://f.10086.cn/im5/login/login.action?type=logout'
url_msg='http://f.10086.cn/im5/chat/sendNewGroupShortMsg.action'
TempDir='./minFetionTmp'
Uagent='Mozilla/5.0'
LOGIN="$TempDir/.fetion.login"

read_cfg() {
  while read -r value
  do
    value=${value##^[[:space]]+}
    value=${value%%[[:space]]+}
    case "$value" in
      user=*)
	user=${value##user=};;
      password=*)
	password=${value##password=};;
      *);;
    esac
  done
  echo "user=$user, password=$password"
}

throw() {
  echo "$*" >&2
  exit 1
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
  time=${js_loader##[^=]*=}
  wget -q -P ${TempDir} --load-cookies=${TempDir}/cookie -U ${Uagent} --keep-session-cookies ${url_base}/${js_loader} -O ${TempDir}/loader.js

  time=$(($time+3500))
  wget -q -P ${TempDir} --load-cookies=${TempDir}/cookie -U ${Uagent} --keep-session-cookies "${url_base}/systemimage/verifycode${time}.png?tp=im5&t=${time}" -O ${TempDir}/code1.png

  time=$(($time+10))
  wget -q -P ${TempDir} --load-cookies=${TempDir}/cookie -U ${Uagent} --keep-session-cookies "${url_base}/systemimage/verifycode${time}.png?tp=im5&t=${time}" -O ${TempDir}/code2.png

  parse_captcha_code

# Special notice: we need to update the cookie here.
  wget -q -P ${TempDir} --load-cookies=${TempDir}/cookie -U ${Uagent} --keep-session-cookies --save-cookies=${TempDir}/cookie --post-data "m=${user}&pass=${password}&captchaCode=${code}&checkCodeKey=null" "${url_login}?t=$(($time+40000))" -O ${TempDir}/loginHtml5.action

  #cat ${TempDir}/loginHtml5.action
  #cp ${TempDir}/loginHtml5.action ${TempDir}/login.action
  #echo ""
:
#arg_t=`tokenize < ${TempDir}/loginHtml5.action | parse | grep -e '^\[\"headurl\"]'| awk '{print $2}'|sed 's/"//g' | grep -Eo 't=\w+'`
  headurl=`tokenize < ${TempDir}/loginHtml5.action | parse | grep -e '^\[\"headurl\"]'| awk '{print $2}'| sed 's/"//g'`
#arg_t="t=$((time+10000))"
  #echo ${headurl}
  #echo ${arg_t}
  idUser=`tokenize < ${TempDir}/loginHtml5.action | parse | grep -e '^\[\"idUser\"]'| awk '{print $2}'|sed 's/"//g'`
  #echo ${idUser}

  wget -q -P ${TempDir} --load-cookies=${TempDir}/cookie -U ${Uagent} --keep-session-cookies  --referer=${url_init} ${headurl}

  touch $LOGIN
}

send_msg() {
  if [ $# -eq 0 ] ; then return; fi
  local msg=$1
  arg_t="t=$((time+20000))"
  wget -q -P ${TempDir} --load-cookies=${TempDir}/cookie -U ${Uagent} --keep-session-cookies --post-data "msg=${msg}&touserid=%2c${idUser}" --referer=${url_init} ${url_msg}?${arg_t} -O ${TempDir}/send_msg.action

  tokenize < ${TempDir}/send_msg.action | parse | grep -e '^\[\"info\"]'|awk '{print $2}'| sed 's/"//g' > ${TempDir}/send_msg.result
}

# Keep seesion alive till logout.
keep_alive() {
  while [ -e $LOGIN ]; do
    url_keepalive="${url_base}/box/alllist.action"
    wget -q -P ${TempDir} --load-cookies=${TempDir}/cookie -U ${Uagent} --keep-session-cookies --post-data "" ${url_keepalive}?${arg_t} -O ${TempDir}/keep_alive.action #t=`make_argt`
    echo "Keep alive: `date`"
    sleep 15
  done
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


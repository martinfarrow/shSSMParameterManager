#!/bin/bash

function usage() {
  cat << EOF

  setup_ssm.sh -a action1,action2,action3... [-d data_file] [-F ssm-function-path] [-k key_id] [pattern]
  setup_ssm.sh -a duplicate -D targetDir [-d data_file] [-F ssm-function-path] [-S replacement] pattern
  
  Options
  =======
  -a: define a comma seperated list of actions, valid values are
        delete           : delete parameters - be very careful with this action it will delete
                           everything 'under' the parameter pattern you provide.

        display          : display the value of local and ssm paramters
                           Note if the parameters are files, or large parameters
                           md5sums are displayed in place of values

        duplicate        : copy the current parameters into the provide path (-D)
                           so that an upload can be executed

        get              : output the parameter values to stdout

        list             : list parameters from the data_file
        matching         : list parameters that match their ssm value from the data_file

        need_updating    )
        needs_updating   ) list parameters that differ from their ssm value
        needs_update     ) 

        update           : update the ssm parameter store to the value in the local file

  -d: data_file, read parameter definitions fromt the data_file
      if data_file isn't supplied then the value of the environment varable SSMDATA is
      used as the path to the data_file

  -D: Duplicate directory, parameters will be downloaded and an ssmData will be created
      in this directory

  -F: path to the ssm-functions.sh file, provided in this repo. If not supplied the value
      of the environment variable SSM_FUNCTION_PATH is used or the default value of 
      ./ssm-functions.sh

  -h: Output help on the parameter file format

  -k: Set the key_id for encrypting parameters, if this is not set the value of the environment
      variable KEY_ID is used.

  -S: Substitute for pattern in ssmData (used in the duplication process)

  Arguments
  =========

  pattern: a pattern for the ssm parameter, things like /stage or /stage/repo
           if pattern is not supplied patterns are read from stdin

  Notes
  =====
  1. action2 is only done if action1 returns true. For instance an action string of
     
       needs_updating,display
  
     will only run the display command on lines that need updating

  2. you can pipeline commands

     You might do something like
     
       $ setup_ssm.sh -a needs_updating,display 

     to find out what needs updating and how the values have changed, then do

       $ setup_ssm.sh -a needs_updating /stage/repo | setup_ssm.sh -a update 

     to update all the parameters.

     Then you might do 

       $ setup_ssm.sh -a display /stage/repo 

     to check the updates

     You could of course do this in one go

       $ setup_ssm.sh -a needs_updating /stage/repo | setup_ssm.sh -a update | setup_ssm.sh -a display
      
     To find the values that need updating, update them and then display the new values, confirming
     that they got updated

  3. You can create a duplicate structure

     $ setup_ssm.sh -a duplicate -D duplicateDir /prod/preprod
 
     will create a ssmData in duplicateDir and grab copies of all the files stored in parameter store

     $ setup_ssm.sh -a duplicate -D duplicate -S /prod/production /prod/preprod

     will do the same as above, but will also rewrite the paths in ssmData to match the substitue 
     path
  
 
     
EOF
}

function parameter_file_help() {
  cat << EOF
  The parameter file is a file of colon (:) delimited lines thus:

    type:ssm parameter path:paramter value

  where 'type' is
    n - for a standard parameter
    f - for a parameter loaded from a file
    l - for a large parameter (over 4096 bytes) loaded from a file

  the 'ssm parameter path', is the path in aws parameter store you with to store your values,
  not that you can't have colons in any of the values

  and 'value' is either the string value of the parameter or the path to the file you wish to
  load/inspect etc.

  some examples;

  n:/stage/qa/database/root/username:root
  f:/stage/certs/some.domain.or.other/key.pem:./certs/key.pem 
  l:stage/usertest/php/parameterfile:./envfiles/qa/dealmaker.m4

  Notes
  =====
  lines begining with '#' are ignored as comments.

EOF
}

action=""
key_id=""
ssm_function_path="./ssm-functions.sh"
dupDir=""
subValue=""
dupFlag=0
subFlag=0

  if [[ ! -z ${SSMDATA} ]];then
    dataFile="$SSMDATA"
  fi

  if [[ ! -z ${KEY_ID} ]];then
    key_id="${KEY_ID}"
  fi

  if [[ ! -z ${SSM_FUNCTION_PATH} ]];then
    ssm_function_path="$SSM_FUNCTION_PATH"
  fi


  while getopts ":a:d:hk:F:D:S:" option $@
  do
    case "${option}" in 
      a) action="${OPTARG}";;
      d) dataFile="${OPTARG}";;
      \?) usage;exit 0;;
      h) parameter_file_help;exit 0;;
      k) key_id=${OPTARG};;
      F) ssm_function_path="${OPTARG}";;
      D) dupFlag=1;dupDir="${OPTARG}";;
      S) subFlag=1;subValue="${OPTARG}";;
    esac
  done

  shift $((OPTIND -1))

  if [[ $key_id == "" ]];then
    echo "You must set the key_id either with -k or KEY_ID env variable"
    exit 1
  fi

  pattern="-"

  if [[ $# -eq 1 ]];then
    pattern="$1"
  fi

  if [[ ! -r $dataFile ]];then
    echo "Cannot read data file \"$dataFile\""
    exit 1
  fi

  if [[ $action == "" ]];then
    echo "You must supply an action with the -a option"
    exit 1
  fi

  if [[ ${ssm_function_path} == "" ]];then
    echo "You must supply the path to the ssm_fuctions.sh file, either with the -F options by setting the environment variable SSM_FUNCTION_PATH"
    exit 1
  fi

  if [[ ! -r ${ssm_function_path} ]];then
    echo "Cannot read the ssm-functions.sh file \"$ssm_function_path\""
    exit 1
  fi

  if [[ $dupFlag -eq 1 ]] && [[ ! -d ${dupDir} ]];then
    echo "Directory ($dupDir) isn't a directory"
    exit 1
  fi

  if [[ $subFlag -eq 1 ]] && [[ $dupFlag -eq 0 ]];then
    echo "Error -S (substitute option) requires -D (duplicate option)"
    exit 1
  fi

   . ${ssm_function_path}

function setParams() {
  oIFS="${IFS}"
  IFS=":"
  set $line
  IFS="${oIFS}"
  ptype=$1
  ppath=$2
  pvalue=$3
}
function filter() {
  if [[ $line =~ ^[fln]:$pattern ]];then 
    setParams "$line"
    return 1
  else
    return 0
  fi
}
function parseFile() {
  grep -v '^#' $dataFile  
}

function check_ssm_value() {
  local res
  res=0
  case "$ptype" in
    n) ssmvalue=$(get_parameter "$ppath")
       [[ $ssmvalue == $pvalue ]] && res=1
       ;;
    f) 
      if [[ ! -r "$pvalue" ]];then
        echo "Cannot locate file $pvalue"
        return 0
      fi
      md5param=$(get_parameter "$ppath" | doMD5 )
      md5local=$(cat "$pvalue" | doMD5)
      [[ $mdparam == $mdlocal ]] && res=1
      ;;
    l)
      if [[ ! -r "$pvalue" ]];then
        echo "Cannot locate file $pvalue"
        return 0
      fi
      get_large_parameter "$ppath" > /tmp/_setup_ssm.$$
      md5param=$(cat /tmp/_setup_ssm.$$ | md5)
      md5local=$(cat "$pvalue" | md5)
      rm /tmp/_setup_ssm.$$
      [[ $mdparam == $mdlocal ]] && res=1
      ;;
  esac
  return $res
}

function get_ssm_value(){
  local res
  res=0
  echo "$ppath"
  case "$ptype" in
    n) 
      get_parameter "$ppath"
      ;;
    f) 
      if [[ ! -r "$pvalue" ]];then
        echo "Cannot locate file $pvalue"
        return 0
      fi
      get_parameter "$ppath" 
      ;;
    l)
      if [[ ! -r "$pvalue" ]];then
        echo "Cannot locate file $pvalue"
        return 0
      fi
      get_large_parameter "$ppath" 
      ;;
  esac
  return 1
}
function trimPath() {
  local start
  start="$1"
  pathToTrim="$2"
  echo $pathToTrim | 
    awk -F '/' 'BEGIN{ slash=""; start='$start' }
                { 
                  for(i=start+2;i<=NF;i++){
                    printf("%s%s",slash,$i);
                    slash="/";
                  }
                }'
}

function duplicate() {
  local target depth rpath
  echo $ppath
  depth=$(echo $pattern | tr -d -c '[/]' | wc -c | tr -d ' ')
  target=$(trimPath $depth $ppath)
  if [[ $subFlag -eq 1 ]];then
    rpath=$subValue/$target
  else
    rpath=$ppath
  fi
  case "$ptype" in 
    n)   result=$(get_ssm_value |tail -1)
         echo "$ptype:$rpath:$result" >> $dupDir/ssmData;;
    f|l) 
         mkdir -p $dupDir/$(dirname $target)
         get_ssm_value > $dupDir/$target
         echo "$ptype:$rpath:./$target" >> $dupDir/ssmData;;
  esac
}

function display_ssm_value(){
  local res result op
  check_ssm_value
  res=$?
  if [[ $res -eq 0 ]];then
    result="DIFFER"
    op="!="
  else
    result="MATCH"
    op="=="
  fi

  echo "type=$ptype, parameter=$ppath, value=$pvalue"
  case "$ptype" in
    n) echo "$result:${ssmvalue} $op ${pvalue}";;
    f|l) echo "$result:${md5param} $op ${md5local}";;
  esac
  return 1
}

function list_ssm_config(){
  echo "$line"
  return 1
}

function need_updating(){
  local res
  check_ssm_value
  res=$?
  if [[ $res -eq 0 ]];then
    echo "$ppath"
    return 1
  else
    return 0
  fi
}

function matching(){
  local res
  check_ssm_value
  res=$?
  [[ $res -eq 1 ]] && echo "$ppath"
  return $res
}

function delete(){
  echo "$ppath"
  case "$ptype" in
    n|f) delete_parameter "$ppath";;
    l) delete_large_parameter "$ppath";;
  esac
  return 1
}

function update(){
  case "$ptype" in
    n) put_parameter "$ppath" "$pvalue"; echo $ppath;;
    f) put_parameter -f "$pvalue" "$ppath"; echo $ppath;;
    l) put_large_parameter -f "$pvalue" "$ppath"; echo $ppath;;
  esac
  return 1
}

  if [[ $pattern == "-" ]];then
    patterns=""
    while read pat
    do
      patterns="$patterns $pat"
    done
  else
    patterns="$pattern"
  fi

  parseFile | while read line
  do
    for pattern in $patterns
    do
      filter
      if [[ $? -eq 1 ]];then
        last=1
        for myaction in $(echo $action | tr '[A-Z]' '[a-z]' | sed "s/,/ /g") 
        do
          case "$myaction" in
            display)       [[ $last -eq 1 ]] && display_ssm_value;;
            list)          [[ $last -eq 1 ]] && list_ssm_config;;
            matching)      [[ $last -eq 1 ]] && matching;;
            need_updating|needs_updating|needs_update) [[ $last -eq 1 ]] && need_updating;; 
            update)        [[ $last -eq 1 ]] && update;;
            delete)        [[ $last -eq 1 ]] && delete;;
            get)           [[ $last -eq 1 ]] && get_ssm_value;;
            duplicate)     [[ $last -eq 1 ]] && duplicate;;
            *) echo "Unknown action \"$myaction\""
               exit 1;;
          esac
          last=$?
        done
      fi
    done
  done


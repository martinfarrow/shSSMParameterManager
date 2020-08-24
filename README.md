# ssmParameterManager
Shell code to manage ssm parameter store using aws cli.

```sh
  setup_ssm.sh -a action1,action2,action3... [-d data_file] 
                         [-F ssm-function-path] [-k key_id] [pattern]
```

The data file format is described below.
  
## Options
  
  - -a: define a comma seperated list of actions, valid values are:

        delete           : delete parameters - be very careful with this action it will delete
                           everything 'under' the parameter pattern you provide.
  
        display          : display the value of local and ssm parameters
                           Note if the parameters are files, or large parameters
                           md5sums are displayed in place of values

        get              : output the parameter values to stdout

        list             : list parameters from the data_file
        matching         : list parameters that match their ssm value from the data_file

        need_updating    )
        needs_updating   ) list parameters that differ from their ssm value
        needs_update     ) 

        update           : update the ssm parameter store to the value in the local file

  - -d: data_file, read parameter definitions from the path `data_file`. If `data_file` isn't supplied then the value of the environment varable `SSMDATA` is used as the path to the data_file

  - -F: path to the `ssm-functions.sh` file, provided in [AWSssmParameterFunction Repo](https://github.com/martinfarrow/AWSssmParameterFunctions).
     If not supplied the value of the environment variable `SSM_FUNCTION_PATH` is used and finally the default value of 
      `./ssm-functions.sh` is taken if not other values are given.

  - -h: Output help on the parameter file format.

  - -k: Set the key_id for encrypting parameters, if this is not set the value of the environment
      variable `KEY_ID` is used.

## Arguments

  pattern: a pattern for the ssm parameter, things like /stage or /stage/repo
           if pattern is not supplied patterns are read from stdin

## Notes

action2 is only done if action1 returns true. For instance an action string of;

`needs_updating,display`
       
will only run the display command on lines from the `data_file` that need updating.

### Pipelining Commands
  
You might do something like;
       
``` 
setup_ssm.sh -a needs_updating,display
```

to find out what needs updating and how the values have changed, then do

       setup_ssm.sh -a needs_updating /stage/repo | setup_ssm.sh -a update 
       
to update all the parameters.

Then you might issue the command;

```
setup_ssm.sh -a display /stage/repo 
```

to check the updates

You could of course do this in one go

```
setup_ssm.sh -a needs_updating /stage/repo | setup_ssm.sh -a update | setup_ssm.sh -a display
```
      
which will find the values that need updating, update them and then display the new values, so you can confirm that they got updated.

## Data file format

 The parameter file is a file of colon (:) delimited lines thus:
 
 `type:ssm parameter path:paramter value`

### Type
 
 `type` is
  
   - n - for a standard parameter
   - f - for a parameter loaded from a file
   - l - for a large parameter (over 4096 bytes) loaded from a file

### ssm parameter path

The `ssm parameter path`, is the path in aws parameter store in which you wish to store values, note that you can't have colons in any of the values.

### Value

`value` is either the string value of the parameter or the path to the file you wish to load/inspect etc.

###Examples
```
  n:/stage/qa/database/root/username:root
  f:/stage/certs/some.domain.or.other/key.pem:./certs/key.pem 
  l:/stage/usertest/php/parameterfile:./envfiles/qa/parameter.m4
```

## Notes
 
Lines begining with `#` are ignored as comments.
     

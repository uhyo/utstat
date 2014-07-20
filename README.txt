# utstat
utstat is a silly tool to build a static web site.

## how to use
install utstat.

 npm install -g utstat

Make `site.utstat.json` at the root source directory.

 {
   "site-name":"name of your web site",
   "output:":"../output"
 }

Make `index.utstat.json` at each directory. (see below)

run `utstat` in the source directory. (or `utstat -h source-directory/`)

Each `.jade`,`.ect` file will be converted to `.html` file.

## index.utstat.json

 {
   "template":"../templates/main.jade",
   "renderer":{
     "type":"jade"
   }
 }

`template` is the relative path to jade file. Each file is processed and passed to this template file as the local variable `content`. Templates can be nested.

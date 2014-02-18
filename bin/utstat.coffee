path=require 'path'
parseArgs=require 'minimist'
utstat=require '../src'


argv=parseArgs process.argv.slice(2),{
    boolean:["h","here","s","silent"]
}
here=argv.h||argv.here
silent=argv.s||argv.silent
pos=argv._[0]

if pos?
    pos=path.resolve process.cwd(),pos
else if here
    pos=process.cwd()

option={}
if silent
    option.log_level=0
else
    option.log_level=1

if pos?
    option.parseTop=pos

utstat.build(pos ? process.cwd())

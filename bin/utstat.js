#!/usr/bin/env node

var path=require('path'), parseArgs=require('minimist'), utstat=require('../src');

var argv = parseArgs(process.argv.slice(2),{
  boolean: ["h", "here", "s", "silent","v"]
});

var here = argv.h || argv.here;
var silent = argv.s || argv.silent;
var verbose=argv.v;

var pos = argv._[0];

if(pos!=null){
  pos = path.resolve(process.cwd(), pos);
}else if(here){
  pos = process.cwd();
}

var option = {};

if(verbose){
  option.log_level = 2;
}else if(silent){
  option.log_level = 0;
} else {
  option.log_level = 1;
}

if (pos != null) {
  option.parseTop = pos;
}

utstat.build((pos ? pos : process.cwd()),option);

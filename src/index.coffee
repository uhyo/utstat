build=require './build'
config=require './config'
path=require 'path'

class Utstat
    build:(dir,callback)->
        dir=path.resolve dir
        builder=new build.Builder config,dir
        builder.build callback




# export
module.exports=new Utstat

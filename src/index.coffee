build=require './build'
config=require './config'
path=require 'path'

class Utstat
    build:(dir,option,callback)->
        if !callback? && "function"==typeof option
            # option省略
            callback=option
            option={}
        # configを拡張
        conf=Object.create config
        for key,value of option
            conf[key]=value
        dir=path.resolve dir
        builder=new build.Builder conf,dir
        builder.build callback


# export
module.exports=new Utstat

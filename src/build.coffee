fs=require 'fs'
path=require 'path'
jade=require 'jade'

class Builder
    #config: config.coffee
    constructor:(@config,@dir)->
    # このディレクトリでビルドする
    build:(callback)->
        # site topを探す
        @findTop (dirpath,sitecontent)=>
            try
                siteobj=JSON.parse sitecontent
            catch e
                console.error "Could not parse #{path.join dirpath,@config.site_file}"
                throw e
            finally
                @registerSite dirpath,siteobj
    # サイトのトップディレクトリを探す
    findTop:(callback)->
        _find=(dir)=>
            filepath=path.join dir,@config.site_file
            fs.readFile filepath,{encoding:@config.encoding},(err,data)=>
                unless err?
                    # ok!
                    callback dir,data
                else if dir!="/"
                    _find path.join dir,".."
                else
                    # 無かった
                    throw new Error "Could not find #{@config.site_file}"
        _find path.normalize @dir

    # ディレクトリを確保
    ensureDir:(dir,callback)->
        fs.stat dir,(err,stat)=>
            if err?
                # ファイルがないかも
                fs.mkdir dir,0o755,(err)->
                    if err?
                        console.error "Could not make directory #{dir}"
                        callback err
                    else
                        # ディレクトリをつくった
                        callback null
            else
                if stat.isDirectory()
                    # OK!
                    callback null
                else
                    # なんだ?
                    console.error "#{dir} is not directory."
                    callback new Error "#{dir} is not directory."

    # サイト情報をゲットして走査開始するぞ!!!!!!!!!!!!!!!!
    registerSite:(sitedir,siteobj)->
        @siteobj=siteobj
        output=siteobj.output
        unless output?
            throw new Error "No output field."
        outdir=path.join sitedir,output
        # 現在の状態を作る
        currentState={}
        ###
        # renderer: テンプレートの関数
        #
        #
        ###
        @directory sitedir,outdir,currentState

    # ディレクトリをビルドする
    directory:(indir,outdir,currentState,callback)->
        @ensureDir outdir,(err)=>
            if err?
                throw err
            # まずindexファイルを読んでみる
            indexfile=path.join indir,@config.index_file
            fs.readFile indexfile,{encoding:@config.encoding},(err,data)=>
                unless err?
                    try
                        indexobj=JSON.parse data
                    catch e
                        console.error "Error reading #{indexfile}"
                        throw e
                    finally
                        currentState=Object.create currentState
                        if indexobj.template?
                            templatefile=path.join indir,indexobj.template
                            fs.readFile templatefile,{encoding:@config.encoding},(err,data)=>
                                if err?
                                    console.error "Error processing #{indexfile}"
                                    throw err

                                currentState.renderer=jade.compile data,{
                                    filename:templatefile
                                    pretty:true
                                    self:false
                                    debug:false
                                    compileDebug:false
                                }
                                do nextStep
                else
                    do nextStep
            # indexを読み終わったのでディレクトリを列挙する
            nextStep= =>
                fs.readdir indir,(err,files)=>
                    if err
                        throw err
                    index=0
                    _onefile=(index)=>
                        if index>=files.length
                            # おわり
                            if callback?
                                callback()
                            return
                        filename=files[index]
                        # 全ファイルを走査する!!!!!!!
                        filepath=path.join indir,filename
                        result=filename.match /^(.*)\.jade$/
                        if result?
                            # このファイルは変換する
                            outpath=path.join outdir,"#{result[1]}.#{@config.extension}"
                            jade.renderFile filepath,{
                                filename:filepath
                                pretty:true
                            },(err,html)=>
                                if err?
                                    console.error "Error rendering #{filepath}"
                                    throw err
                                # マスターに突っ込む
                                if "function"!=typeof currentState.renderer
                                    console.error "Error processing #{filepath}"
                                    throw new Error "No renderer is set."
                                renderresult=currentState.renderer {
                                    content:html
                                }
                                # 書き込む

                                fs.writeFile outpath,renderresult,{
                                    encoding:@config.encoding
                                },(err)->
                                    if err?
                                        console.error "Error processing #{filepath}"
                                        throw err
                                    # 次へ
                                    process.nextTick ->
                                        _onefile index+1
                        else
                            # 関係ないファイルか?
                            fs.stat filename,(err,stat)=>
                                if err?
                                    # 無視して次へ
                                    _onefile index+1
                                else
                                    if stat.isDirectory()
                                        # 中を走査する
                                        @directory filepath,path.join(outdir,filename),currentState,->
                                            _onefile index+1
                                    else
                                        _onefile index+1
                    _onefile 0


        







# export
exports.Builder=Builder

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
        # frameRenderer: テンプレートの関数
        # renderer: 拡張子ごとのやつ
        #
        ###
        currentState.renderer=
            ".jade":(builder,filepath,outdir,currentState,callback)->
                res=path.basename filepath,".jade"
                builder.renderFile filepath,outdir,res+builder.config.extension,currentState,callback
        # 依存関係ファイルをチェックする
        dependpath=path.join sitedir,@config.dependencies_file
        # @dependencies
        ###
        # files: {filepath: mtime}
        # depends: {from: [to]}
        #
        ###
        # このファイルが新しいか古いか確かめる
        @newtable={} # {filepath: boolean}
        fs.readFile dependpath,{
            encoding:@config.encoding
        },(err,data)=>
            if err?
                # ないから新規に作成
                @dependencies=
                    files:{}
                    depends:{}
            else
                try
                    @dependencies=JSON.parse data
                catch e
                    console.error "#{dependpath} may be broken. Remove the file to build full site."
                    throw e
            @directory sitedir,outdir,currentState,=>
                # 終了したら依存関係を保存
                fs.writeFile dependpath,JSON.stringify(@dependencies),{
                    encoding:@config.encoding
                },(err)=>
                    if err?
                        console.error "Error writing #{dependpath}"
                        throw err

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

                                currentState.frameRenderer=jade.compile data,{
                                    filename:templatefile
                                    pretty:true
                                    self:false
                                    debug:false
                                    compileDebug:false
                                }
                                do nextStep
                        else
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
                        @isNew filepath,(state,isdir)=>
                            if isdir
                                # ディレクトリは中を走査する
                                @directory filepath,path.join(outdir,filename),currentState,->
                                    _onefile index+1
                                return
                            if state==false
                                # このファイルは新しくない
                                _onefile index+1
                                return

                            # ファイルをアレする
                            ext=path.extname filepath
                            func=currentState.renderer[ext]
                            unless func?
                                # 対応するレンダラはない
                                _onefile index+1
                            else
                                # レンダリングする
                                func this,filepath,outdir,currentState,->
                                    process.nextTick ->
                                        _onefile index+1
                    _onefile 0
    # このファイルが更新されているかどうか
    isNew:(filepath,callback)->
        if @newtable[filepath]?
            # trueかfalse
            callback @newtable[filepath]
            return
        fs.stat filepath,(err,stat)=>
            if err?
                # なにこれ
                @newtable[filepath]=false
                callback false
                return
            if stat.isDirectory()
                # ディレクトリは常に見よう
                callback true,true
                return
            # 比べる
            if !@dependencies.files[filepath]? || @dependencies.files[filepath]<stat.mtime.getTime()
                @dependencies.files[filepath]=stat.mtime.getTime()
                @newtable[filepath]=true
                callback true
                return
            # このファイルは変更されていない。依存関係を調べる
            @newtable[filepath]=false #無限ループ防止に一旦false
            files=@dependencies.depends[filepath]
            unless Array.isArray files
                # 依存関係なし
                callback false
                return
            some=false
            _check=(index)=>
                if index>=files.length
                    # ないね
                    if some
                        # 依存先が新しくなっていたりした
                        @newtable[filepath]=true
                        callback true
                    else
                        callback false
                    return
                dfilepath=files[index]
                @isNew dfilepath,(state)->
                    some ||= state
                    _check index+1
            _check 0


    # ひとつrenderする
    renderFile:(filepath,outdir,outname,currentState,local,callback)->
        if !callback? && "function"==typeof local
            callback=local
            local={}
        dir=path.dirname filepath
        outpath=path.join outdir,outname
        opt=Object.create local
        opt.filename=filepath
        opt.pretty=true

        jade.renderFile filepath,opt,(err,html)=>
            if err?
                console.error "Error rendering #{filepath}"
                throw err
            # マスターに突っ込む
            if "function"!=typeof currentState?.frameRenderer
                console.error "Error processing #{filepath}"
                throw new Error "No renderer is set."
            renderresult=currentState.frameRenderer {
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
                callback()









# export
exports.Builder=Builder

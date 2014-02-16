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
        @sitedir=sitedir
        @siteobj=siteobj
        output=siteobj.output
        unless output?
            throw new Error "No output field."
        @outdir=path.resolve sitedir,output
        # 現在の状態を作る
        currentState={}
        ###
        # frameRenderer: テンプレートの関数
        # renderer: レンダリングする関数
        #
        ###
        currentState.renderer=(filepath,outdir,currentState,callback)=>
            ext=path.extname filepath
            if ext==".jade"
                res=path.basename filepath,".jade"
                @renderFile filepath,path.join(outdir,res+@config.extension),currentState,callback
            else
                # 何もしない
                callback()
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
            @directory sitedir,".",currentState,=>
                # 終了したら依存関係を保存
                fs.writeFile dependpath,JSON.stringify(@dependencies),{
                    encoding:@config.encoding
                },(err)=>
                    if err?
                        console.error "Error writing #{dependpath}"
                        throw err

    # ディレクトリをビルドする
    directory:(indir,relativedir,currentState,callback)->
        odir=path.join @outdir,relativedir
        @ensureDir odir,(err)=>
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
                                nextStep indexobj
                        else
                            nextStep indexobj
                else
                    nextStep null
            # レンダラも読み込んだりして
            nextStep=(indexobj)=>
                if indexobj?.renderer
                    rendererfile=require path.join indir,indexobj.renderer
                    rendererobj=rendererfile.getRenderer this
                    currentState.renderer=rendererobj.render
                do nextStep2
            # indexを読み終わったのでディレクトリを列挙する
            nextStep2= =>
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
                        relpath=path.join relativedir,filename
                        @isNew filepath,relpath,(state,isdir)=>
                            if isdir
                                # ディレクトリは中を走査する
                                @directory filepath,relpath,currentState,->
                                    _onefile index+1
                                return
                            if state==false
                                # このファイルは新しくない
                                _onefile index+1
                                return

                            # ファイルをアレする
                            # レンダリングする
                            currentState.renderer filepath,odir,currentState,->
                                process.nextTick ->
                                    _onefile index+1
                    _onefile 0
    # このファイルが更新されているかどうか
    isNew:(filepath,relpath,callback)->
        if @newtable[relpath]?
            # trueかfalse
            callback @newtable[relpath]
            return
        fs.stat filepath,(err,stat)=>
            if err?
                # なにこれ
                @newtable[relpath]=false
                callback false
                return
            if stat.isDirectory()
                # ディレクトリは常に見よう
                callback true,true
                return
            # 比べる
            if !@dependencies.files[relpath]? || @dependencies.files[relpath]<stat.mtime.getTime()
                @dependencies.files[relpath]=stat.mtime.getTime()
                @newtable[relpath]=true
                callback true
                return
            # このファイルは変更されていない。依存関係を調べる
            @newtable[relpath]=false #無限ループ防止に一旦false
            files=@dependencies.depends[relpath]
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
                        @newtable[relpath]=true
                        callback true
                    else
                        callback false
                    return
                dfilepath=files[index]
                realpath=path.resolve @sitedir,dfilepath
                @isNew realpath,dfilepath,(state)->
                    some ||= state
                    _check index+1
            _check 0


    # ひとつrenderする
    renderFile:(filepath,outpath,currentState,local,callback)->
        if !callback? && "function"==typeof local
            callback=local
            local={}
        dir=path.dirname filepath
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

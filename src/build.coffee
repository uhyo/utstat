fs=require 'fs'
path=require 'path'
jade=require 'jade'

# 現在の状態
class State
    ###
    # frameRenderer: テンプレートの関数
    # middleRenderer: 間にはさむテンプレートの関数
    # renderer: レンダリングする関数
    # defaultDependencies: デフォルトで依存する
    # dir: 現在処理しているディレクトリ（相対パス）
    ###
    constructor:(@builder)->
        @frameRenderer=null
        @renderer=null
        @middleRenderer=[]
        @defaultDependencies=[]
        @dir=null
    # 新しいの
    clone:->
        res=new State @builder
        res.frameRenderer=@frameRenderer
        res.renderer=@renderer
        res.middleRenderer=@middleRenderer.concat []
        res.defaultDependencies=@defaultDependencies.concat []
        res.dir=@dir
        res
    # 依存先ファイルを追加
    # paths: (現在のディレクトリからの相対パス）
    addDependency:(paths)->
        unless Array.isArray paths
            paths=[paths]
        for p in paths
            @defaultDependencies.push path.relative @builder.sitedir,path.resolve @builder.sitedir,@dir,p
        return
    # レンダー関数を追加
    addMiddleRenderer:(func)->
        @middleRenderer.push func
        return
    # 新しいjadeテンプレートを間に追加
    addMiddleTemplate:(filepath,callback)->
        templatefile=path.resolve @builder.sitedir,@dir,filepath
        @builder.loadTemplate templatefile,(err,func)=>
            if err?
                callback err
                return
            @addDependency filepath
            @addMiddleRenderer func
            callback null
        return


class Builder
    #config: config.coffee
    constructor:(@config,@dir)->
        # テンプレートのキャッシュ（ファイル名）
        @templateCache={}
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
        if @config.log_level>=2
            console.log "stating from",sitedir
        @sitedir=sitedir
        @siteobj=siteobj
        output=siteobj.output
        unless output?
            throw new Error "No output field."
        @outdir=path.resolve sitedir,output
        # 現在の状態を作る
        currentState=new State this
        currentState.renderer=(filepath,currentState,callback)=>
            ext=path.extname filepath
            if ext==".jade"
                res=path.basename filepath,".jade"
                @renderFile filepath,res+@config.extension,currentState,callback
            else
                # 何もしない
                callback()
        currentState.middleRenderer=[]
        currentState.defaultDependencies=[]
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
        if @config.parseTop? && /(?:^|\/)\.\.(?:$|\/)/.test path.relative @config.parseTop,indir
            # ここは方向が違う
            do callback
            return
        if @config.log_level>=2
            console.log "entering directory",indir
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
                        currentState=currentState.clone()
                        currentState.dir=relativedir
                        currentState.addDependency @config.index_file
                        if indexobj.template?
                            templatefile=path.join indir,indexobj.template
                            fs.readFile templatefile,{encoding:@config.encoding},(err,data)=>
                                if err?
                                    console.error "Error processing #{indexfile}"
                                    throw err

                                currentState.addDependency indexobj.template
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
            nextStep=(indexobj)=>
                # レンダラ読み込み
                if indexobj?.renderer
                    switch typeof indexobj.renderer
                        when "string"
                            # カスタムレンダラ（ファイル）
                            rendererpath=path.join indir,indexobj.renderer
                            rendererfile=require rendererpath
                            rendererobj=rendererfile.getRenderer this
                            if "function"==typeof rendererobj.render
                                currentState.renderer=rendererobj.render

                            currentState.addDependency indexobj.renderer

                            if "function"==typeof rendererobj.afterRender
                                currentState.addMiddleRenderer ((func)->(obj)->func obj.content,obj.page)(rendererobj.afterRender)
                        when "object"
                            # 簡易カスタム
                            switch indexobj.renderer.type
                                when "static"
                                    # 拡張子によってそのままアレする
                                    currentState.renderer=((exts,builder)->
                                        (filepath,currentState,callback)->
                                            ext=path.extname filepath
                                            if exts=="*" || exts.indexOf(ext)>=0
                                                # これはアレする
                                                builder.keepFile filepath,currentState,callback
                                            else
                                                # 他は無視
                                                do callback
                                    )(indexobj.renderer.exts,this)
                                when "jade"
                                    # 普通にjadeをレンダリング
                                    # コピペだけど......
                                    currentState.renderer=(filepath,currentState,callback)=>
                                        ext=path.extname filepath
                                        if ext==".jade"
                                            res=path.basename filepath,".jade"
                                            @renderFile filepath,res+@config.extension,currentState,callback
                                        else
                                            # 何もしない
                                            callback()
                                when "none"
                                    # このディレクトリはレンダリングしない
                                    do callback
                                    return

                # middle-template読み込み
                if indexobj["middle-template"]?
                    mids=indexobj["middle-template"]
                    unless Array.isArray mids
                        mids=[mids]
                    _onetemp=(index)=>
                        if index>=mids.length
                            # 次へ
                            nextStep2 indexobj
                            return
                        currentState.addMiddleTemplate mids[index],(err)->
                            if err?
                                console.error "Error processing #{indexfile}"
                                throw err
                            _onetemp index+1
                    _onetemp 0
                else
                    nextStep2 indexobj
            # indexを読み終わったのでディレクトリを列挙する
            nextStep2= =>
                fs.readdir indir,(err,files)=>
                    if err
                        throw err
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
                        if relpath==@config.dependencies_file
                            # これは走査する必要なし
                            _onefile index+1
                            return

                        # 依存関係更新
                        deps=@dependencies.depends[relpath] ? []
                        @dependencies.depends[relpath]=unique deps.concat currentState.defaultDependencies
                        # ユニーク以外は消す
                        @isNew filepath,relpath,(state,isdir)=>
                            if isdir
                                delete @dependencies.depends[relpath]
                                # ディレクトリは中を走査する
                                @directory filepath,relpath,currentState,->
                                    _onefile index+1
                                return
                            if state==false
                                # このファイルは新しくない
                                _onefile index+1
                                return
                            if @config.log_level>0
                                console.log "processing #{relpath}"

                            # ファイルをアレする
                            # レンダリングする
                            currentState.renderer filepath,currentState,->
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
    # 中間テンプレートを読み込んでキャッシュする
    # templatefile: 絶対パス
    loadTemplate:(templatefile,callback)->
        if @templateCache[templatefile]?
            callback null,@templateCache[templatefile]
            return
        fs.readFile templatefile,{encoding:@config.encoding},(err,data)=>
            if err?
                console.error "error reading #{templatefile}"
                callback err,null
                return
            func=jade.compile data,{
                filename:templatefile
                pretty:true
            }
            @templateCache[templatefile]=func
            callback null,func
        return


    # # # # 公開API的な何か
    # そのまま
    keepFile:(filepath,currentState,callback)->
        outpath=path.join @outdir,currentState.dir,path.basename filepath
        rs=fs.createReadStream filepath
        rs.on "error",(err)->
            console.error "Error copying #{filepath} to #{outpath}"
            throw err
        ws=fs.createWriteStream outpath
        ws.on "error",(err)->
            console.error "Error copying #{filepath} to #{outpath}"
            throw err
        ws.on "close",->
            do callback
        rs.pipe ws
    # ひとつrenderする
    renderFile:(filepath,outname,currentState,local,callback)->
        if !callback? && "function"==typeof local
            callback=local
            local={}
        dir=path.dirname filepath
        # ページ情報
        page={}
        site=
            name:@siteobj["site-name"]

        opt=Object.create local
        opt.page=page
        opt.site=site
        opt.filename=filepath
        opt.pretty=true
        outpath=path.join @outdir,currentState.dir,outname

        jade.renderFile filepath,opt,(err,html)=>
            if err?
                console.error "Error rendering #{filepath}"
                throw err
            # マスターに突っ込む
            if "function"!=typeof currentState?.frameRenderer
                console.error "Error processing #{filepath}"
                throw new Error "No renderer is set."
            frs=[currentState.frameRenderer].concat currentState.middleRenderer
            #renderresult=currentState.frameRenderer {
            #    content:html
            #}
            content=html
            for func in frs by -1
                opt.content=content
                content=func opt
            # 書き込む
            fs.writeFile outpath,content,{
                encoding:@config.encoding
            },(err)->
                if err?
                    console.error "Error processing #{filepath}"
                    throw err
                # 次へ
                callback()
    dependon:(frompath,topath)->
        # 1回目の依存関係チェックはいらない?
        frel=path.relative @sitedir,frompath
        trel=path.relative @sitedir,topath
        if Array.isArray @dependencies.depends[frel]
            @dependencies.depends[frel]=unique @dependencies.depends[frel].concat trel
        else
            @dependencies.depends[frel]=[trel]



#util
unique=(arr)->
    result=[]
    table={}
    for value in arr
        unless table[value]?
            table[value]=true
            result.push value
    result





# export
exports.Builder=Builder

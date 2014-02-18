# Default Config
prefix=".utstat"

module.exports=
    log_level:0
    encoding:"utf8"
    site_file:"site#{prefix}.json"
    index_file:"index#{prefix}.json"
    dependencies_file:".dependencies#{prefix}.json"
    extension:".html"
    parseTop:null   # ここから下だけ走査する（絶対パスじゃん）





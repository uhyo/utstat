var path=require('path');

//Custom Renderer
exports.getRenderer=function(builder){
	var data=require('./data.js');
	return {
		render:function(filepath,currentState,callback){
			//ページが分裂
			//var ext=path.extname(filepath);
			//if(ext===".jade"){
			var base=path.basename(filepath);
			if(base==="index.jade"){
				builder.dependon(filepath,path.join(__dirname,"data.js"));
				var base=path.basename(filepath,".jade");
				(function l(i){
					if(i>=3){
						callback();
						return;
					}
					builder.renderFile(filepath,base+i+".html",currentState,{index:i,d:data.myData[i]},l.bind(null,i+1));
				})(0);
			}else{
				callback();
			}
		},
		afterRender:function(content){
			return content.replace(/\[\[foo\]\]/g,"<a href='/foo'>foo</a>");
		},
	};
};

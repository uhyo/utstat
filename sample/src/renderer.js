var path=require('path');

//Custom Renderer
exports.getRenderer=function(builder){
	return {
		render:function(filepath,outdir,currentState,callback){
			//ページが分裂
			var ext=path.extname(filepath);
			if(ext===".jade"){
				var base=path.basename(filepath,".jade");
				(function l(i){
					if(i>=3){
						callback();
						return;
					}
					builder.renderFile(filepath,path.join(outdir,base+i+".html"),currentState,{index:i},l.bind(null,i+1));
				})(0);
			}
		}
	};
};

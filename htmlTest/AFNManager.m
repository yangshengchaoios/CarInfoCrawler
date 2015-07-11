//
//  AFNManager.m
//  YSCKit
//
//  Created by  YangShengchao on 14-5-4.
//  Copyright (c) 2014年 yangshengchao. All rights reserved.
//

#import "AFNManager.h"

@implementation AFNManager


/**
 *  发起get & post & 上传图片 请求
 *
 *  @param url              接口前缀 最后的'/'可有可无
 *  @param apiName          方法名称 前面不能有'/'
 *  @param arrayParam       数组参数，用来组装url/param1/param2/param3，参数的顺序很重要
 *  @param dictParam        字典参数，key-value
 *  @param imageData        图片资源
 *  @param requestType      RequestTypeGET 和 RequestTypePOST
 *  @param requestSuccessed 请求成功的回调
 *  @param requestFailure   请求失败的回调
 */
+ (void)requestByUrl:(NSString *)url
           dictParam:(NSDictionary *)params
         requestType:(RequestType)requestType
    requestSuccessed:(RequestSuccessed)requestSuccessed
      requestFailure:(RequestFailure)requestFailure {
    
	//5. 发起网络请求
    AFHTTPRequestOperationManager *manager = [AFHTTPRequestOperationManager manager];   //create new AFHTTPRequestOperationManager
    manager.responseSerializer = [AFHTTPResponseSerializer serializer];//TODO:针对返回数据不规范的情况
    manager.requestSerializer.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    manager.requestSerializer.timeoutInterval = 20;//设置POST和GET的超时时间
    
    //   定义返回成功的block
    void (^requestSuccessed1)(AFHTTPRequestOperation *operation, id responseObject) = ^(AFHTTPRequestOperation *operation, id responseObject) {
        //如果返回的数据是编过码的，则需要转换成字符串，方便输出调试
        if ([responseObject isKindOfClass:[NSData class]]) {
            NSStringEncoding gbkEncoding = CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingGB_18030_2000);
            responseObject = [[NSString alloc] initWithData:responseObject encoding:gbkEncoding];
        }
        if (requestSuccessed) {
            requestSuccessed(responseObject);
        }
    };
    //   定义返回失败的block
    void (^requestFailure1)(AFHTTPRequestOperation *operation, NSError *error) = ^(AFHTTPRequestOperation *operation, NSError *error) {
        NSLog(@"request failed! \r\noperation=%@\r\nerror=%@", operation, error);
        if (200 != operation.response.statusCode) {
            if (401 == operation.response.statusCode) {
                if (requestFailure) {
                    requestFailure(1003, @"您还未登录呢！");
                }
            }
            else {
                if (requestFailure) {
                    requestFailure(1004, @"网络错误！");
                }
            }
        }
        else {
            if (requestFailure) {
                requestFailure(200, error.localizedDescription);
            }
        }
    };
	if (RequestTypeGET == requestType) {
		NSLog(@"getting data...");
		[manager   GET:url
		    parameters:params
		       success:requestSuccessed1
		       failure:requestFailure1];
	}
	else if (RequestTypePOST == requestType) {
		NSLog(@"posting data...");
		[manager  POST:url
		    parameters:params
		       success:requestSuccessed1
		       failure:requestFailure1];
	}
}

@end

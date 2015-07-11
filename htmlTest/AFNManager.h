//
//  AFNManager.h
//  YSCKit
//
//  Created by  YangShengchao on 14-5-4.
//  Copyright (c) 2014年 yangshengchao. All rights reserved.
//  FORMATED!
//

#import "AFNetworking.h"

#pragma mark - block定义

typedef void (^RequestSuccessed)(id responseObject);
typedef void (^RequestFailure)(NSInteger errorCode, NSString *errorMessage);

typedef NS_ENUM (NSInteger, RequestType) {
	RequestTypeGET = 0,
	RequestTypePOST,
};


@interface AFNManager : NSObject


#pragma mark - 通用的GET、POST和上传图片（返回JSONModel的所有内容）

+ (void)requestByUrl:(NSString *)url
           dictParam:(NSDictionary *)params
         requestType:(RequestType)requestType
    requestSuccessed:(RequestSuccessed)requestSuccessed
      requestFailure:(RequestFailure)requestFailure;

@end

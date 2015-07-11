//
//  ServyouAppDelegate.m
//  htmlTest
//
//  Created by khuang on 14-8-21.
//  Copyright (c) 2014年 servyou. All rights reserved.
//

#import "ServyouAppDelegate.h"
#import "TFHpple.h"
#import "AFNManager.h"
#import <FMDB/FMDB.h>

#define DocumentsPath       (((NSArray *)NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES))[0])
#define DBCarRealPath       [DocumentsPath stringByAppendingPathComponent:@"yckx_car.sqlite"]      //数据库在沙盒中的路径
#define DBCarProgramPath    [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"yckx_car.sqlite"]


#define FileDefaultManager              [NSFileManager defaultManager]
#define PrefixUrl @"http://car.autohome.com.cn/AsLeftMenu/As_LeftListNew.ashx"
#define WeakSelfType __weak __typeof(&*self)

@implementation ServyouAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    NSLog(@"%@", DocumentsPath);
    NSLog(@"real=%@", DBCarRealPath);
    NSLog(@"%@", DBCarProgramPath);
    if ([FileDefaultManager fileExistsAtPath:DBCarRealPath]) {
        [FileDefaultManager removeItemAtPath:DBCarRealPath error:nil]; //if not delete it, error will happen!
    }
    [FileDefaultManager copyItemAtPath:DBCarProgramPath toPath:DBCarRealPath error:nil];

    [self performSelectorInBackground:@selector(startRefreshModelList) withObject:nil];
    
    return YES;
}




//--------------------------
//
// 第一步：更新品牌
//
//--------------------------
//更新一级品牌列表
- (void)refreshBrandList {
    [AFNManager requestByUrl:PrefixUrl
                   dictParam:@{@"typeId" : @"1", @"brandId" : @"0"}
                 requestType:RequestTypeGET
            requestSuccessed:^(id responseObject) {
                NSString *brandListDiv = [responseObject stringByReplacingOccurrencesOfString:@"document.writeln(\"" withString:@"<div>"];
                brandListDiv = [brandListDiv stringByReplacingOccurrencesOfString:@"\");" withString:@"</div>"];
                
                TFHpple *doc = [TFHpple hppleWithXMLData:[brandListDiv dataUsingEncoding:NSUTF8StringEncoding] encoding:@"UTF-8"];
                NSArray * items = [doc searchWithXPathQuery:@"//a"];
                
                NSString *logFilePath = [DocumentsPath stringByAppendingPathComponent:@"/failedLog"];//日志目录
                if ([[NSFileManager defaultManager] fileExistsAtPath:logFilePath]) {
                    [[NSFileManager defaultManager] removeItemAtPath:logFilePath error:nil];
                }
                for (TFHppleElement *item in items) {
                    NSString *href = item.attributes[@"href"];
                    NSString *brandCode = [href stringByReplacingOccurrencesOfString:@"/price/brand-" withString:@""];
                    brandCode = [brandCode stringByReplacingOccurrencesOfString:@".html" withString:@""];
                    NSString *brandName = ((TFHppleElement *)item.children[1]).content;
                    NSString *brandPinyin = [self toPinYin:brandName];
                    NSString *insertSql = [NSString stringWithFormat:@"INSERT INTO temp_brand(brandCode,brandName,pinyin) VALUES('%@','%@','%@')", brandCode, brandName, brandPinyin];
                    BOOL isSuccess = [self sqliteUpdate:insertSql];
                    if (isSuccess) {
                        NSLog(@"%@", insertSql);
                    }
                    else {
                        NSString *failedBrand = [NSString stringWithFormat:@"code[%@],name[%@],pinyin[%@]", brandCode, brandName, brandPinyin];
                        NSLog(@"failed!!! %@", failedBrand);
                        [self saveLog:failedBrand intoFilePath:logFilePath];
                    }
                }
            } requestFailure:^(NSInteger errorCode, NSString *errorMessage) {
                NSLog(@"errorMsg = %@", errorMessage);
            }];
}


//--------------------------
//
// 第二步：更新车组及车系
//
//--------------------------
//启动更新二级品牌及车系线程
- (void)startRefreshBrandList {
    NSArray *brandArray = [self brandArray];
    for (NSString *brandId in brandArray) {
        [self performSelectorInBackground:@selector(refreshBrandGroupAndSeriesList:) withObject:brandId];
        while (NO == self.isFinished) {
            [NSThread sleepForTimeInterval:3];
        }
    }
}
//更新二级品牌及车系列表
//调用方法：[self performSelectorInBackground:@selector(startRefreshBrandList) withObject:nil];
- (void)refreshBrandGroupAndSeriesList:(NSString *)brandId {
    self.isFinished = NO;
    WeakSelfType blockSelf = self;
    [AFNManager requestByUrl:PrefixUrl
                   dictParam:@{@"typeId" : @"1", @"brandId" : brandId}
                 requestType:RequestTypeGET
            requestSuccessed:^(id responseObject) {
                NSString *brandListDiv = [responseObject stringByReplacingOccurrencesOfString:@"document.writeln(\"" withString:@"<div>"];
                brandListDiv = [brandListDiv stringByReplacingOccurrencesOfString:@"\");" withString:@"</div>"];
                
                TFHpple *doc = [TFHpple hppleWithXMLData:[brandListDiv dataUsingEncoding:NSUTF8StringEncoding] encoding:@"UTF-8"];
                NSArray * items = [doc searchWithXPathQuery:@"//dl"];
                
                NSString *logFilePath = [DocumentsPath stringByAppendingPathComponent:@"/failedLog"];//日志目录
                if ([[NSFileManager defaultManager] fileExistsAtPath:logFilePath]) {
                    [[NSFileManager defaultManager] removeItemAtPath:logFilePath error:nil];
                }
                NSString *lastBrandCode = @"";
                for (TFHppleElement *item in ((TFHppleElement *)items[0]).children) {
                    TFHppleElement *firstItem = item.firstChild;
                    NSString *href = firstItem.attributes[@"id"];
                    if ([@"dt" isEqualToString:item.tagName]) {
                        NSString *parentCode = brandId;
                        NSString *brandCode = [href stringByReplacingOccurrencesOfString:@"fct_" withString:@""];
                        NSString *brandName = ((TFHppleElement *)firstItem.children[1]).content;
                        NSString *brandPinyin = [self toPinYin:brandName];
                        NSString *insertSql = [NSString stringWithFormat:@"INSERT INTO temp_brand1(brandCode,brandName,pinyin,parentCode) VALUES('%@','%@','%@','%@')", brandCode, brandName, brandPinyin, parentCode];
                        [blockSelf addNewRow:insertSql filePath:logFilePath];
                        lastBrandCode = brandCode;
                    }
                    else if ([@"dd" isEqualToString:item.tagName]) {
                        NSString *seriesCode = [href stringByReplacingOccurrencesOfString:@"series_" withString:@""];
                        NSString *brandCode = lastBrandCode;
                        NSString *seriesName = ((TFHppleElement *)firstItem.children[0]).content;
                        NSString *onSale = @"1";
                        if ([firstItem.raw rangeOfString:@"停售"].location != NSNotFound) {
                            onSale = @"0";
                        }
                        NSString *insertSql = [NSString stringWithFormat:@"INSERT INTO temp_series(seriesCode,brandCode,seriesName,onSale) VALUES('%@','%@','%@','%@')", seriesCode, brandCode, seriesName, onSale];
                        [blockSelf addNewRow:insertSql filePath:logFilePath];
                    }
                }
                blockSelf.isFinished = YES;
            } requestFailure:^(NSInteger errorCode, NSString *errorMessage) {
                blockSelf.isFinished = YES;
                NSLog(@"errorMsg = %@", errorMessage);
            }];
}


//--------------------------
//
// 第三步：更新车型
//
//--------------------------
//启动更新车型数据库线程
- (void)startRefreshModelList {
    NSArray *seriesArray = [self seriesArray];
    for (NSString *seriesId in seriesArray) {
        [self performSelectorInBackground:@selector(refreshModelList:) withObject:seriesId];
        while (NO == self.isFinished) {
            [NSThread sleepForTimeInterval:1];
        }
    }
}
//更新车型列表
//用法：遍历两次，一次是在售车型url；另一次是停售车型url
//调用方法：[self performSelectorInBackground:@selector(startRefreshModelList) withObject:nil];
- (void)refreshModelList:(NSString *)seriesId {
    self.isFinished = NO;
    WeakSelfType blockSelf = self;
    //http://car.autohome.com.cn/price/series-135.html
    NSString *url = [NSString stringWithFormat:@"http://car.autohome.com.cn/price/series-%@.html", seriesId];//在售车型
    //    url = [NSString stringWithFormat:@"http://car.autohome.com.cn/price/series-%@-0-3-0-0-0-0-1.html", seriesId];//停售车型
    [AFNManager requestByUrl:url
                   dictParam:nil
                 requestType:RequestTypeGET
            requestSuccessed:^(id responseObject) {
                NSString *responseString = [NSString stringWithFormat:@"%@", responseObject];
                TFHpple *doc = [TFHpple hppleWithHTMLData:[responseString dataUsingEncoding:NSUTF8StringEncoding] encoding:@"UTF-8"];
                NSArray * items = [doc searchWithXPathQuery:@"//div[@class=\"interval01 \"]"];
                NSString *onSale = @"1";
                if ([items count] == 0) {
                    items = [doc searchWithXPathQuery:@"//div[@class=\"interval01 interval02\"]"];
                }
                if ([url rangeOfString:@"-0-3-0-0-0-0-1.html"].location != NSNotFound && [items count] == 0) {//停售(单独调用的时候才启动)
                    items = [doc searchWithXPathQuery:@"//div[@class=\"interval01 interval01-sale\"]"];
                    onSale = @"0";
                }
                
                NSString *logFilePath = [DocumentsPath stringByAppendingPathComponent:@"/failedLog"];//日志目录
                if ([[NSFileManager defaultManager] fileExistsAtPath:logFilePath]) {
                    [[NSFileManager defaultManager] removeItemAtPath:logFilePath error:nil];
                }
                for (TFHppleElement *item in items) {
                    NSArray *priceArray = [item searchWithXPathQuery:@"//span[@class=\"guidance-price\"]"];
                    NSArray *engineArray = [item searchWithXPathQuery:@"//span[@class=\"interval01-list-cars-text\"]"];
                    NSArray *nameArray = [item searchWithXPathQuery:@"//p[@class=\"infor-title\"]/a[1]"];
                    TFHppleElement *engineElement = engineArray[0];
                    NSString *modelEngine = ((TFHppleElement *)engineElement.children[0]).content;
                    modelEngine = [modelEngine stringByReplacingOccurrencesOfString:@"升" withString:@"L"];
                    modelEngine = [modelEngine stringByReplacingOccurrencesOfString:@"马力" withString:@"KW"];
                    if ([@"0" isEqualToString:onSale]) {
                        modelEngine = @"";//停售的车型默认engine
                    }
                    for (int i = 0; i < [priceArray count]; i++) {
                        TFHppleElement *priceElement = priceArray[i];
                        TFHppleElement *nameElement = nameArray[i];
                        NSString *modelCode = nameElement.attributes[@"href"];
                        modelCode = [modelCode stringByReplacingOccurrencesOfString:@"http://www.autohome.com.cn/spec/" withString:@""];
                        modelCode = [modelCode stringByReplacingOccurrencesOfString:@"/" withString:@""];
                        
                        NSString *modelName = ((TFHppleElement *)nameElement.children[0]).content;
                        NSArray *tempArray = [modelName componentsSeparatedByString:@" "];
                        if ([tempArray count] > 2) {
                            modelName = [NSString stringWithFormat:@"%@ %@", tempArray[1], tempArray[2]];
                        }
                        else {
                            modelName = [NSString stringWithFormat:@"%@", tempArray[1]];
                        }
                        
                        NSString *modelYear = tempArray[0];
                        modelYear = [modelYear stringByReplacingOccurrencesOfString:@"款" withString:@""];
                        
                        NSString *modelPrice = ((TFHppleElement *)priceElement.children[0]).content;
                        modelPrice = [modelPrice stringByReplacingOccurrencesOfString:@"万" withString:@""];
                        
                        NSString *insertSql = [NSString stringWithFormat:@"INSERT INTO temp_model(seriesCode,modelCode,modelYear,modelName,modelEngine,modelPrice,onSale) VALUES('%@','%@','%@','%@','%@','%@','%@')", seriesId, modelCode, modelYear, modelName, modelEngine, modelPrice, onSale];
                        [blockSelf addNewRow:insertSql filePath:logFilePath];
                    }
                }
                blockSelf.isFinished = YES;
            } requestFailure:^(NSInteger errorCode, NSString *errorMessage) {
                blockSelf.isFinished = YES;
                NSLog(@"errorMsg = %@", errorMessage);
            }];
}



//--------------------------
//
// 公共方法
//
//--------------------------
- (void)addNewRow:(NSString *)insertSql filePath:(NSString *)logFilePath {
    BOOL isSuccess = [self sqliteUpdate:insertSql];
    if (isSuccess) {
        NSLog(@"%@", insertSql);
    }
    else {
        NSLog(@"failed!!!");
        [self saveLog:insertSql intoFilePath:logFilePath];
    }
}
- (void)saveLog:(NSString *)logString intoFilePath:(NSString *)logFilePath {
    NSFileHandle* fh = [NSFileHandle fileHandleForWritingAtPath:logFilePath];
    if ( ! fh ) {
        [[NSFileManager defaultManager] createFileAtPath:logFilePath contents:nil attributes:nil];
        fh = [NSFileHandle fileHandleForWritingAtPath:logFilePath];
    }
    @try {
        [fh seekToEndOfFile];
        [fh writeData:[logString dataUsingEncoding:NSUTF8StringEncoding]];
    }
    @catch (NSException *exception) {
        
    }
    @finally {
        
    }
    [fh closeFile];
}
- (NSArray *)brandArray {
    NSString *dbPath = DBCarRealPath;
    FMDatabase *db = [FMDatabase databaseWithPath:dbPath];
    NSMutableArray *array = [NSMutableArray array];
    if ([db open]) {
        NSString *selectSql = [NSString stringWithFormat:@"SELECT brandCode FROM temp_brand"];
        FMResultSet *resultSet = [db executeQuery:selectSql];
        while ([resultSet next]) {
            [array addObject:[resultSet stringForColumn:@"brandCode"]];
        }
    }
    [db close];
    return array;
}
- (NSArray *)seriesArray {
    NSString *dbPath = DBCarRealPath;
    FMDatabase *db = [FMDatabase databaseWithPath:dbPath];
    NSMutableArray *array = [NSMutableArray array];
    if ([db open]) {
        NSString *selectSql = [NSString stringWithFormat:@"SELECT seriesCode FROM temp_series ORDER BY seriesId ASC"];
        FMResultSet *resultSet = [db executeQuery:selectSql];
        while ([resultSet next]) {
            [array addObject:[resultSet stringForColumn:@"seriesCode"]];
        }
    }
    [db close];
    return array;
}
- (BOOL)sqliteUpdate:(NSString *)sql {
    NSString *dbPath = DBCarRealPath;
    BOOL isSuccess = NO;
    FMDatabase *db = [FMDatabase databaseWithPath:dbPath];
    if ([db open]) {
        isSuccess = [db executeUpdate:sql];
    }
    [db close];
    return isSuccess;
}
- (NSString *)toPinYin:(NSString *)string {
    NSMutableString *mutableString = [NSMutableString stringWithString:string];
    CFStringTransform((CFMutableStringRef)mutableString, NULL, kCFStringTransformToLatin, false);
    mutableString = (NSMutableString *)[mutableString stringByFoldingWithOptions:NSDiacriticInsensitiveSearch locale:[NSLocale currentLocale]];
    NSArray *tempArray = [mutableString componentsSeparatedByString:@" "];
    NSMutableString *firstLetterArray = [NSMutableString string];
    for (NSString *letter in tempArray) {
        [firstLetterArray appendString:[letter substringToIndex:1].uppercaseString];
    }
    return [NSString stringWithString:firstLetterArray];
}





//--------------------------
//
// AppDelegate相关回调方法
//
//--------------------------
- (void)applicationWillResignActive:(UIApplication *)application
{
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later. 
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
    // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
}

- (void)applicationWillTerminate:(UIApplication *)application
{
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
}

@end

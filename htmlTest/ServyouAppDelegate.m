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

    //第一步：下载车品牌(更新表：yckx_car_brand)
//    [self refreshBrandList];
    //第二步：下载车组+车系(更新表：yckx_car_brand和yckx_car_series)
//    [self performSelectorInBackground:@selector(startRefreshBrandList) withObject:nil];
    //第三步：下载在售和停售的车型(更新表：yckx_car_model)
//    [self performSelectorInBackground:@selector(startRefreshModelList) withObject:nil];//NOTE:这里要执行两次(在售+停售)
    //第四步：更新停售车型的modelEngine
    [self performSelectorInBackground:@selector(startRefreshModelEngineList) withObject:nil];
    //第五步：更新model里的brandId(更新表：yckx_car_model)
//    UPDATE yckx_car_model SET brandId = (SELECT brandId FROM yckx_car_series WHERE yckx_car_model.seriesId = yckx_car_series.seriesId)
    //第六步：压缩数据库。执行命令：VACUUM
    
    NSLog(@"运行完成！");
    return YES;
}

//--------------------------
//
// 第一步：更新品牌
//
//--------------------------
//更新一级品牌列表
- (void)refreshBrandList {
    [self sqliteUpdate:@"DELETE FROM yckx_car_brand"];
    WeakSelfType blockSelf = self;
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
                    NSString *brandId = [href stringByReplacingOccurrencesOfString:@"/price/brand-" withString:@""];
                    brandId = [brandId stringByReplacingOccurrencesOfString:@".html" withString:@""];
                    NSString *brandName = ((TFHppleElement *)item.children[1]).content;
                    NSString *brandPinyin = [self toPinYin:brandName];
                    NSString *insertSql = [NSString stringWithFormat:@"INSERT INTO yckx_car_brand(brandId,brandName,brandPinyin) VALUES('%@','%@','%@')", brandId, brandName, brandPinyin];
                    [blockSelf addNewRow:insertSql filePath:logFilePath];
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
    [self sqliteUpdate:@"DELETE FROM yckx_car_brand WHERE brandParentId <> 0"];
    [self sqliteUpdate:@"DELETE FROM yckx_car_series"];
    NSArray *brandArray = [self brandArray];
    for (NSString *brandId in brandArray) {
        self.isFinished = NO;
        [self performSelectorInBackground:@selector(refreshBrandGroupAndSeriesList:) withObject:brandId];
        while (NO == self.isFinished) {
            [NSThread sleepForTimeInterval:1];
        }
    }
}
//更新二级品牌及车系列表
//调用方法：[self performSelectorInBackground:@selector(startRefreshBrandList) withObject:nil];
- (void)refreshBrandGroupAndSeriesList:(NSString *)brandId {
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
                NSInteger lastBrandId = 0;
                for (TFHppleElement *item in ((TFHppleElement *)items[0]).children) {
                    TFHppleElement *firstItem = item.firstChild;
                    NSString *href = firstItem.attributes[@"id"];
                    if ([@"dt" isEqualToString:item.tagName]) {
                        NSString *brandParentId = brandId;
                        NSString *brandName = ((TFHppleElement *)firstItem.children[1]).content;
                        NSString *brandPinyin = [self toPinYin:brandName];
                        NSString *insertSql = [NSString stringWithFormat:@"INSERT INTO yckx_car_brand(brandName,brandPinyin,brandParentId,brandOnSale) VALUES('%@','%@','%@',1)", brandName, brandPinyin, brandParentId];
                        [blockSelf addNewRow:insertSql filePath:logFilePath];
                        lastBrandId = [self selectLastRow:[NSString stringWithFormat:@"select brandId from yckx_car_brand order by brandId desc limit 0,1"]];
                    }
                    else if ([@"dd" isEqualToString:item.tagName]) {
                        NSString *seriesId = [href stringByReplacingOccurrencesOfString:@"series_" withString:@""];
                        NSString *seriesName = ((TFHppleElement *)firstItem.children[0]).content;
                        NSString *onSale = @"1";
                        if ([firstItem.raw rangeOfString:@"停售"].location != NSNotFound) {
                            onSale = @"0";
                        }
                        NSString *insertSql = [NSString stringWithFormat:@"INSERT INTO yckx_car_series(seriesId,brandId,seriesName,seriesOnSale) VALUES('%@',%ld,'%@','%@')", seriesId, (long)lastBrandId, seriesName, onSale];
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
//    [self sqliteUpdate:@"DELETE FROM yckx_car_model WHERE seriesId>=0"];
    NSArray *seriesArray = [self seriesArray];
    for (NSString *seriesId in seriesArray) {
        self.isFinished = NO;
        [self performSelectorInBackground:@selector(refreshModelList:) withObject:seriesId];
        while (NO == self.isFinished) {
            [NSThread sleepForTimeInterval:2];
        }
    }
}
//更新车型列表
//用法：遍历两次，一次是在售车型url；另一次是停售车型url
//调用方法：[self performSelectorInBackground:@selector(startRefreshModelList) withObject:nil];
- (void)refreshModelList:(NSString *)seriesId {
    WeakSelfType blockSelf = self;
    NSString *url = [NSString stringWithFormat:@"http://car.autohome.com.cn/price/series-%@.html", seriesId];//在售车型
    url = [NSString stringWithFormat:@"http://car.autohome.com.cn/price/series-%@-0-3-0-0-0-0-1.html", seriesId];//停售车型
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
                        NSString *modelId = nameElement.attributes[@"href"];
                        modelId = [modelId stringByReplacingOccurrencesOfString:@"http://www.autohome.com.cn/spec/" withString:@""];
                        modelId = [modelId stringByReplacingOccurrencesOfString:@"/" withString:@""];
                        
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
                        
                        NSString *insertSql = [NSString stringWithFormat:@"INSERT INTO yckx_car_model(modelId,seriesId,modelYear,modelName,modelEngine,modelPrice,modelOnSale) VALUES('%@','%@','%@','%@','%@','%@','%@')", modelId, seriesId, modelYear, modelName, modelEngine, modelPrice, onSale];
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
// 第四步：更新modelEngine
//
//--------------------------
- (void)startRefreshModelEngineList {
    NSArray *modelArray = [self modelArray];
    for (NSString *modelId in modelArray) {
        self.isFinished = NO;
        [self performSelectorInBackground:@selector(refreshModelEngineList:) withObject:modelId];
        while (NO == self.isFinished) {
            [NSThread sleepForTimeInterval:1];
        }
    }
}
//调用方法：[self performSelectorInBackground:@selector(refreshModelEngineList) withObject:nil];
- (void)refreshModelEngineList:(NSString *)modelId {
    //http://www.autohome.com.cn/spec/2247
    NSString *url = [NSString stringWithFormat:@"http://www.autohome.com.cn/spec/%@", modelId];
    WeakSelfType blockSelf = self;
    [AFNManager requestByUrl:url
                   dictParam:@{}
                 requestType:RequestTypeGET
            requestSuccessed:^(id responseObject) {
                NSString *responseString = [NSString stringWithFormat:@"%@", responseObject];
//                TFHpple *doc = [TFHpple hppleWithHTMLData:[responseString dataUsingEncoding:NSUTF8StringEncoding] encoding:@"UTF-8"];
                //<li><span>发&nbsp;动&nbsp;机：</span>
//                NSInteger startIndex = [responseString substringFromIndex:1];
                //<li class="cardetail-right"><span>变&nbsp;速&nbsp;箱：
                
                NSRange r1 = [responseString rangeOfString:@"<li><span>发&nbsp;动&nbsp;机：</span>"];
                NSRange r2 = [responseString rangeOfString:@"<li class=\"cardetail-right\"><span>变&nbsp;速&nbsp;箱："];
                NSRange rSub = NSMakeRange(r1.location + r1.length, r2.location - r1.location - r1.length);
                NSString *modelEngine = [responseString substringWithRange:rSub];
                modelEngine = [modelEngine stringByReplacingOccurrencesOfString:@"马力" withString:@"KW"];
                modelEngine = [modelEngine stringByReplacingOccurrencesOfString:@"</li>" withString:@""];
                if ([modelEngine rangeOfString:@"KW"].location != NSNotFound) {
                    NSRange range = [modelEngine rangeOfString:@"KW"];
                    modelEngine = [modelEngine substringToIndex:range.location + range.length];
                }
                NSString *logFilePath = [DocumentsPath stringByAppendingPathComponent:@"/failedLog"];//日志目录
                if ([[NSFileManager defaultManager] fileExistsAtPath:logFilePath]) {
                    [[NSFileManager defaultManager] removeItemAtPath:logFilePath error:nil];
                }
                
                NSString *updateSql = [NSString stringWithFormat:@"UPDATE yckx_car_model SET modelEngine = '%@' WHERE modelId = %@", modelEngine, modelId];
                [blockSelf addNewRow:updateSql filePath:logFilePath];
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
        NSString *selectSql = [NSString stringWithFormat:@"SELECT brandId FROM yckx_car_brand WHERE brandParentId = 0 ORDER BY brandId ASC"];
        FMResultSet *resultSet = [db executeQuery:selectSql];
        while ([resultSet next]) {
            [array addObject:[resultSet stringForColumnIndex:0]];
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
        NSString *selectSql = [NSString stringWithFormat:@"SELECT seriesId FROM yckx_car_series WHERE seriesId>=0 ORDER BY seriesId ASC"];
        FMResultSet *resultSet = [db executeQuery:selectSql];
        while ([resultSet next]) {
            [array addObject:[resultSet stringForColumnIndex:0]];
        }
    }
    [db close];
    return array;
}
//查询出modelEngine为空的modelId
- (NSArray *)modelArray {
    NSString *dbPath = DBCarRealPath;
    FMDatabase *db = [FMDatabase databaseWithPath:dbPath];
    NSMutableArray *array = [NSMutableArray array];
    if ([db open]) {
        NSString *selectSql = [NSString stringWithFormat:@"SELECT modelId FROM yckx_car_model WHERE modelEngine = '' ORDER BY modelId ASC"];
        FMResultSet *resultSet = [db executeQuery:selectSql];
        while ([resultSet next]) {
            [array addObject:[resultSet stringForColumnIndex:0]];
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
- (NSInteger)checkExists:(NSString *)sql {
    NSInteger tempId = -1;
    FMDatabase *db = [FMDatabase databaseWithPath:DBCarRealPath];
    if ([db open]) {
        FMResultSet *resultSet = [db executeQuery:sql];
        while ([resultSet next]) {
            tempId = [resultSet intForColumnIndex:0];
            break;
        }
    }
    [db close];
    return tempId;
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
- (NSInteger)selectLastRow:(NSString *)selectSql {
    NSInteger lastId = 0;
    FMDatabase *db = [FMDatabase databaseWithPath:DBCarRealPath];
    if ([db open]) {
        FMResultSet *resultSet = [db executeQuery:selectSql];
        while ([resultSet next]) {
            lastId = [resultSet intForColumnIndex:0];
        }
    }
    [db close];
    return lastId + 0;
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

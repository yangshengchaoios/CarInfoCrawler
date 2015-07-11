//
//  ServyouViewController.m
//  htmlTest
//
//  Created by khuang on 14-8-21.
//  Copyright (c) 2014年 servyou. All rights reserved.
//

#import "ServyouViewController.h"
#import "TFHpple.h"

@interface ServyouViewController ()
{
    TFHpple *doc;
}
@property (weak, nonatomic) IBOutlet UIWebView *webView;
@property (weak, nonatomic) IBOutlet UIWebView *webView1;
@end

@implementation ServyouViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.
    
    
    //信用等级查询
//    url:'http://hd.chinatax.gov.cn/fagui/action/InitCredit.do' ,
//    type: 'POST',
//    data: {
//    "taxCode":"650000","articleField06":"","pageSize":"30"
//    ,"articleField01":"企业名称查询条件","articleField04":"A类",
//    "cPage":pageIndex
//    },
    NSString* file = [[NSBundle mainBundle] pathForResource:@"XYDJ" ofType:@"htm"];
    NSData * data = [NSData dataWithContentsOfFile:file];
    
    doc = [TFHpple hppleWithHTMLData:data encoding:@"UTF-8"];
    NSArray * items = [doc searchWithXPathQuery:@"//table"];
    for (TFHppleElement *item in items)
    {
        NSString *value = item.attributes[@"class"];
        if (value != nil && [value isEqualToString:@"sv_black14_30"])
        {
            NSArray * tables = [item searchWithXPathQuery:@"//table"];
            if (tables.count > 2)
            {
                TFHppleElement *table = tables[1];
                //叠加每次查询结果
                [self.webView loadHTMLString:[NSString stringWithFormat:@"%@%@", table.raw,table.raw]  baseURL:nil];
                break;
            }
        }
    }
    
    
    //出口退税查询
//    url:'http://hd.chinatax.gov.cn/fagui/action/InitChukou.do' ,
//    type: 'POST',
//    data: {
//        "orderField":"articleField01","desc":"false","pageSize":"30"
//        ,"articleField01":"商品代码查询条件","articleField02":"商品名称查询条件",
//        "cPage":pageIndex
//    },
    NSString* file1 = [[NSBundle mainBundle] pathForResource:@"CKTS" ofType:@"html"];
    NSData * data1 = [NSData dataWithContentsOfFile:file1];
    
    doc = [TFHpple hppleWithHTMLData:data1 encoding:@"UTF-8"];
    NSArray * items1 = [doc searchWithXPathQuery:@"//table"];
    if (items1.count > 4)
    {
        TFHppleElement *table = items1[3];
        NSMutableString *modified = [[NSMutableString alloc] initWithString:@"<table  border=\"0\" cellpadding=\"0\" cellspacing=\"1\" bgcolor=\"#CCCCCC\">"];
        NSRange range = [table.raw rangeOfString:@">"];
        [modified appendString:[table.raw substringFromIndex:range.location + 1]];
        //叠加每次查询结果
        [self.webView1 loadHTMLString:[NSString stringWithFormat:@"%@%@", modified,modified]  baseURL:nil];
    }    
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end

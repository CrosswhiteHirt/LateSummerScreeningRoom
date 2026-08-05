//
//  HSClient.hpp
//  HSSecurity
//
//  Created by Tank on 3/30/23.
//

#ifndef HSSecSdk_hpp
#define HSSecSdk_hpp

#include <iostream>
#import <UIKit/UIKit.h>

// 前向声明
class HSClient;

class HSSetting {
public:
    NSString* company;//公司名称, 由后台分配
    NSString* appId;//应用id, 由后台分配
    NSString* token;//由后台分配
    /** 上报后端：dataeye(生产) / dataeye-dev / dataeye-fat / xvector / mixguard，未传时默认 dataeye */
    NSString* reportBackend;
};

class HSSecSdk {
    
    
public:
    HSSecSdk();
    ~HSSecSdk();
    bool initSDK(HSSetting hsSetting);
    void setUserId(NSString* userId);
    /**
     * @brief 签名x
     * @param reqTime 请求时间, 单位ms，在http请求头需要加上X-Req-Time: reqTime
     * @param path 请求路径, 如: /api/v1/checkTask
     * @param body 请求体, base64编码后传进来, 如果body为空, 则传空字符串
     * @return 签名x, 在http请求头需要加上X-Sign-X: signx
     */
    NSString* signx(long reqTime, NSString* path, NSString* body);
    /** 
     * @brief 签名y
     * @param reqTime 请求时间, 单位ms，在http请求头需要加上X-Req-Time: reqTime
     * @param path 请求路径, 如: /api/v1/checkTask
     * @param body 请求体, base64编码后传进来, 如果body为空, 则传空字符串
     * @return 签名y, 在http请求头需要加上X-Sign-Y: signy
     */
    NSString* signy(long reqTime, NSString* path, NSString* body);
private:
    HSClient* hsClient;
};

#endif /* HSSecSdk_hpp */

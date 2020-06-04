//
//  SJResourceFileManager.m
//  SJMediaCacheServer_Example
//
//  Created by BlueDancer on 2020/6/2.
//  Copyright © 2020 changsanjiang@gmail.com. All rights reserved.
//

#import "SJResourceFileManager.h"
#import <sys/xattr.h>

@implementation SJResourceFileManager
+ (NSString *)rootDirectoryPath {
    static NSString *rootDirectoryPath;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        rootDirectoryPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).lastObject stringByAppendingPathComponent:@"com.SJMediaCacheServer.cache"];
        if ( ![[NSFileManager defaultManager] fileExistsAtPath:rootDirectoryPath] ) {
            [[NSFileManager defaultManager] createDirectoryAtPath:rootDirectoryPath withIntermediateDirectories:YES attributes:nil error:nil];
            const char *filePath = [rootDirectoryPath fileSystemRepresentation];
            const char *attrName = "com.apple.MobileBackup";
            u_int8_t attrValue = 1;
            setxattr(filePath, attrName, &attrValue, sizeof(attrValue), 0, 0);
        }
    });
    return rootDirectoryPath;
}

+ (NSString *)getResourcePathWithName:(NSString *)name {
    return [[self rootDirectoryPath] stringByAppendingPathComponent:name];
}

+ (NSString *)databasePath {
    return [[self rootDirectoryPath] stringByAppendingPathComponent:@"cache.db"];
}

+ (NSString *)getContentFilePathWithName:(NSString *)name inResource:(NSString *)resourceName {
    return [[self getResourcePathWithName:resourceName] stringByAppendingPathComponent:name];
}

+ (NSString *)createContentFileInResource:(NSString *)resourceName atOffset:(NSUInteger)offset {
    @autoreleasepool {
        NSString *resourcePath = [self getResourcePathWithName:resourceName];
        if ( ![NSFileManager.defaultManager fileExistsAtPath:resourcePath] ) {
            [NSFileManager.defaultManager createDirectoryAtPath:resourcePath withIntermediateDirectories:YES attributes:nil error:nil];
        }
        
        NSUInteger sequence = 0;
        while (1) {
            NSString *filename = [NSString stringWithFormat:@"%lu_%lu", (unsigned long)offset, (unsigned long)sequence++];
            NSString *filepath = [self getContentFilePathWithName:filename inResource:resourceName];
            if ( ![NSFileManager.defaultManager fileExistsAtPath:filepath] ) {
                [NSFileManager.defaultManager createFileAtPath:filepath contents:nil attributes:nil];
                return filename;
            }
        }
    }
    return nil;
}
@end
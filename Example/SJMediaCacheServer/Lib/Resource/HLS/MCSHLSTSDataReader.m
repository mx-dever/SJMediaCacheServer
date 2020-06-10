//
//  MCSHLSTSDataReader.m
//  SJMediaCacheServer_Example
//
//  Created by BlueDancer on 2020/6/10.
//  Copyright © 2020 changsanjiang@gmail.com. All rights reserved.
//

#import "MCSHLSTSDataReader.h"
#import "MCSLogger.h"
#import "MCSHLSResource.h"
#import "MCSResourceSubclass.h"
#import "MCSResourceNetworkDataReader.h"
#import "MCSResourceFileDataReader.h"
#import "MCSDownload.h"
#import "MCSUtils.h"
#import "MCSError.h"
#import "MCSResourceManager.h"

@interface MCSHLSTSDataReader ()<MCSDownloadTaskDelegate, NSLocking> {
    NSRecursiveLock *_lock;
}
@property (nonatomic, weak, nullable) MCSHLSResource *resource;
@property (nonatomic, strong) NSURLRequest *request;

@property (nonatomic) BOOL isCalledPrepare;
@property (nonatomic) BOOL isClosed;
@property (nonatomic) BOOL isDone;

@property (nonatomic, strong, nullable) MCSResourcePartialContent *content;
@property (nonatomic) NSUInteger downloadedLength;
@property (nonatomic) NSUInteger offset;

@property (nonatomic, strong, nullable) NSURLSessionTask *task;
@property (nonatomic, strong, nullable) NSFileHandle *reader;
@property (nonatomic, strong, nullable) NSFileHandle *writer;
@end

@implementation MCSHLSTSDataReader
@synthesize delegate = _delegate;

- (instancetype)initWithResource:(MCSHLSResource *)resource request:(NSURLRequest *)request {
    self = [super init];
    if ( self ) {
        _resource = resource;
        _request = request;
        _lock = NSRecursiveLock.alloc.init;
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"%@:<%p> { URL: %@\n };", NSStringFromClass(self.class), self, _request.URL];
}

- (void)prepare {
    if ( _isClosed || _isCalledPrepare )
        return;
    
    MCSLog(@"%@: <%p>.prepare { URL: %@ };\n", NSStringFromClass(self.class), self, _request.URL);

    _isCalledPrepare = YES;
    
    _content = [_resource contentForTsProxyURL:_request.URL];
    if ( _content != nil ) {
        [self _prepare];
    }
    else {
        NSString *tsName = [_resource tsNameForTsProxyURL:_request.URL];
        NSURL *URL = [_resource.parser tsURLWithTsName:tsName];
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:URL];
        [_request.allHTTPHeaderFields enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, NSString * _Nonnull obj, BOOL * _Nonnull stop) {
            [request setValue:obj forHTTPHeaderField:key];
        }];
        _task = [MCSDownload.shared downloadWithRequest:request delegate:self];
    }
}

- (NSData *)readDataOfLength:(NSUInteger)lengthParam {
    [self lock];
    @try {
        if ( _isClosed || _isDone )
            return nil;
        
        NSData *data = nil;
        
        if ( _offset < _downloadedLength ) {
            NSUInteger length = MIN(lengthParam, _downloadedLength - _offset);
            if ( length > 0 ) {
                data = [_reader readDataOfLength:length];
                _offset += data.length;
                _isDone = _offset == _response.totalLength;
                MCSLog(@"%@: <%p>.read { offset: %lu, length: %lu };\n", NSStringFromClass(self.class), self, _offset, data.length);
#ifdef DEBUG
                if ( _isDone ) {
                    MCSLog(@"%@: <%p>.done { URL: %@ };\n", NSStringFromClass(self.class), self, _request.URL);
                }
#endif
            }
        }
        
        return data;
    } @catch (NSException *exception) {
        [self _onError:[NSError mcs_errorForException:exception]];
    } @finally {
        [self unlock];
    }
}

- (void)close {
    [self lock];
    @try {
        if ( _isClosed )
            return;
        
        _isClosed = YES;
        if ( _task.state == NSURLSessionTaskStateRunning ) [_task cancel];
        _task = nil;
        [_writer synchronizeFile];
        [_writer closeFile];
        _writer = nil;
        [_reader closeFile];
        _reader = nil;
        [_content readWrite_release];
    } @catch (__unused NSException *exception) {
        
    } @finally {
        [self unlock];
    }
    
    MCSLog(@"%@: <%p>.close;\n", NSStringFromClass(self.class), self);
}

- (void)_prepare {
    [_content readWrite_retain];
    NSString *filepath = [_resource filePathOfContent:_content];
    _reader = [NSFileHandle fileHandleForReadingAtPath:filepath];
    _writer = [NSFileHandle fileHandleForWritingAtPath:filepath];
    _response = [MCSResourceResponse.alloc initWithServer:@"localhost" contentType:_resource.tsContentType totalLength:_content.tsTotalLength];
    [self.delegate readerPrepareDidFinish:self];
}

#pragma mark -

- (void)downloadTask:(NSURLSessionTask *)task didReceiveResponse:(NSHTTPURLResponse *)response {
    [self lock];
    @try {
        if ( _isClosed )
            return;
        
        NSString *contentType = MCSGetResponseContentType(response);
        NSUInteger totalLength = MCSGetResponseContentLength(response);
        _resource.tsContentType = contentType;
        [MCSResourceManager.shared saveMetadata:_resource];
        _content = [_resource createContentWithTsProxyURL:_request.URL tsTotalLength:totalLength];
        [self _prepare];
    } @catch (__unused NSException *exception) {
        
    } @finally {
        [self unlock];
    }
}

- (void)downloadTask:(NSURLSessionTask *)task didReceiveData:(NSData *)data {
    [self lock];
    @try {
        if ( _isClosed )
            return;
        
        [_writer writeData:data];
        _downloadedLength += data.length;
        _content.length = _downloadedLength;
        
        
    } @catch (NSException *exception) {
        [self _onError:[NSError mcs_errorForException:exception]];
        
    } @finally {
        [self unlock];
    }
    
    [self.delegate readerHasAvailableData:self];
}

- (void)downloadTask:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    [self lock];
    @try {
        if ( _isClosed )
            return;
        
        if ( error != nil && error.code != NSURLErrorCancelled ) {
            [self _onError:error];
        }
        else {
            // finished download
        }
    } @catch (__unused NSException *exception) {
        
    } @finally {
        [self unlock];
    }
}

#pragma mark -

- (void)lock {
    [_lock lock];
}

- (void)unlock {
    [_lock unlock];
}

- (void)_onError:(NSError *)error {
    [self.delegate reader:self anErrorOccurred:error];
}
@end

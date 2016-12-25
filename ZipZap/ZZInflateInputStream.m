//
//  ZZInflateInputStream.m
//  ZipZap
//
//  Created by Glen Low on 29/09/12.
//  Copyright (c) 2012, Pixelglow Software. All rights reserved.
//

#include <zlib.h>

#import "ZZInflateInputStream.h"

static const NSUInteger _bufferLength = 16384; // 16K buffer

@implementation ZZInflateInputStream
{
	NSInputStream* _upstream;
	NSMutableData* _readBuffer;
	NSStreamStatus _status;
	NSError* _error;
	z_stream _stream;
	id<NSStreamDelegate> _delegate;
	BOOL _hasBytesAvailable;
	BOOL _finishedReading;
}

+ (NSData*)decompressData:(NSData*)data
	 withUncompressedSize:(NSUInteger)uncompressedSize
{
	NSMutableData* inflatedData = [NSMutableData dataWithLength:uncompressedSize];
	
	z_stream stream;
	stream.zalloc = Z_NULL;
	stream.zfree = Z_NULL;
	stream.opaque = Z_NULL;
	stream.next_in = (Bytef*)data.bytes;
	stream.avail_in = (uInt)data.length;
	stream.next_out = (Bytef*)inflatedData.mutableBytes;
	stream.avail_out = (uInt)inflatedData.length;
	
	inflateInit2(&stream, -15);
	int result = inflate(&stream, Z_FINISH);
	inflateEnd(&stream);
	
	switch (result)
	{
		case Z_STREAM_END:
			return inflatedData;
		default:
			// TODO: reference some kind of error
			return nil;
	}
}

- (instancetype)initWithStream:(NSInputStream*)upstream
{
	if ((self = [super init]))
	{
		_upstream = upstream;
		
		_readBuffer = [NSMutableData dataWithLength:_bufferLength];
		_status = NSStreamStatusNotOpen;
		_error = nil;
		
		_stream.zalloc = Z_NULL;
		_stream.zfree = Z_NULL;
		_stream.opaque = Z_NULL;
		_stream.next_in = Z_NULL;
		_stream.avail_in = 0;
	}
	return self;
}

- (NSStreamStatus)streamStatus
{
	return _status;
}

- (NSError*)streamError
{
	return _error;
}

- (void)setDelegate:(id<NSStreamDelegate>)delegate
{
	_delegate = delegate;
}

- (id<NSStreamDelegate>)delegate
{
	if (_delegate)
		return _delegate;
	
	return self;
}

- (void)scheduleInRunLoop:(NSRunLoop *)aRunLoop forMode:(NSRunLoopMode)mode
{
}

- (void)removeFromRunLoop:(NSRunLoop *)aRunLoop forMode:(NSRunLoopMode)mode
{	
}

- (BOOL)setProperty:(id)property forKey:(NSStreamPropertyKey)key
{
	return NO;
}

- (id)propertyForKey:(NSStreamPropertyKey)key
{
	return nil;
}

- (void)open
{
	[_upstream open];
	_status = NSStreamStatusOpen;
	_hasBytesAvailable = YES;

	inflateInit2(&_stream, -15);
	
	if ([self.delegate respondsToSelector:@selector(stream:handleEvent:)])
	{
		[self.delegate stream:self handleEvent:NSStreamEventOpenCompleted];
		[self.delegate stream:self handleEvent:NSStreamEventHasBytesAvailable];
	}
}

- (void)close
{
	inflateEnd(&_stream);
	
	[_upstream close];
	_status = NSStreamStatusClosed;
}

- (NSInteger)read:(uint8_t*)buffer maxLength:(NSUInteger)len
{
	if (_finishedReading)
	{
		_status = NSStreamStatusAtEnd;
		_hasBytesAvailable = NO;
		
		if ([self.delegate respondsToSelector:@selector(stream:handleEvent:)])
			[self.delegate stream:self handleEvent:NSStreamEventEndEncountered];
		
		return 0;
	}
	
	// if buffer is empty and stream is still OK, read in up to 16K bytes from upstream
	NSInteger bytesRead;
	if (_stream.avail_in == 0)
		switch (_upstream.streamStatus)
		{
			case NSStreamStatusOpening:
			case NSStreamStatusOpen:
				bytesRead = [_upstream read:_readBuffer.mutableBytes maxLength:_bufferLength];
				if (bytesRead >= 0)
				{
					_stream.next_in = (Bytef*)_readBuffer.bytes;
					_stream.avail_in = (uInt)bytesRead;
				}
				else
				{
					_status = NSStreamStatusError;
					_error = _upstream.streamError;
					_hasBytesAvailable = NO;
					
					if ([self.delegate respondsToSelector:@selector(stream:handleEvent:)])
						[self.delegate stream:self handleEvent:NSStreamEventErrorOccurred];
					
					return -1;
				}
				break;
			default:
				break;
		}

	// zlib available bytes limited to 32 bits
	if (len > UINT_MAX)
		len = UINT_MAX;
		
	// inflate buffer
	_stream.next_out = buffer;
	_stream.avail_out = (uInt)len;
	switch (inflate(&_stream, Z_NO_FLUSH))
	{
		case Z_STREAM_END:
			// Delay sending delegate methods and updating _status until next read to ensure client has finished reading data
			_finishedReading = YES;
			break;
		// TODO: need to handle Z_DATA_ERROR etc.
		default:
			break;
	}
	
	// return how many bytes produced by inflate
	return len - _stream.avail_out;
}

- (BOOL)getBuffer:(uint8_t**)buffer length:(NSUInteger*)len
{
	return NO;
}

- (BOOL)hasBytesAvailable
{
	return _hasBytesAvailable;
}

@end

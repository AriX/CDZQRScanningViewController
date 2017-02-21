//
//  CDZQRScanningViewController.h
//
//  Created by Chris Dzombak on 10/27/13.
//  Copyright (c) 2013 Chris Dzombak. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

typedef void (^CDZQRScanResultBlock)(AVMetadataMachineReadableCodeObject *result);
typedef void (^CDZQRScanErrorBlock)(NSError *error);
typedef void (^CDZQRScanCancelBlock)();

extern NSString * const CDZQRScanningErrorDomain;

typedef NS_ENUM(NSInteger, CDZQRScanningViewControllerErrorCode) {
    CDZQRScanningViewControllerErrorUnavailableMetadataObjectType = 1,
};

/**
 *  Easy barcode scanning view controller for iOS 7.
 */

@interface CDZQRScanningViewController : UIViewController

/**
 *  Returns a scanning view controller configured to accept the given metadata object types.
 *
 *  @param metadataObjectTypes An array of `AVMetadataMachineReadableCodeObject` types
 *
 *  @return Scanning view controller configured to accept the given metadata object types
 */
- (instancetype)initWithMetadataObjectTypes:(NSArray<NSString *> *)metadataObjectTypes;

/**
 *  Returns a scanning view controller configured to accept QR codes
 *
 *  @note This is equivalent to calling `initWithMetadataObjectTypes:@[ AVMetadataObjectTypeQRCode ]`
 *
 *  @return Scanning view controller configured to accept QR codes
 */
- (instancetype)init;

// Your blocks will be called on the main queue.
@property (nonatomic, copy) CDZQRScanResultBlock resultBlock;
@property (nonatomic, copy) CDZQRScanErrorBlock errorBlock;
@property (nonatomic, copy) CDZQRScanCancelBlock cancelBlock;

/**
 *  An array of `AVMetadataMachineReadableCodeObject` types
 */
@property (nonatomic, strong, readonly) NSArray<NSString *> *metadataObjectTypes;

@end

//
//  CDZQRScanningViewController.m
//
//  Created by Chris Dzombak on 10/27/13.
//  Copyright (c) 2013 Chris Dzombak. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>
#import <dispatch/dispatch.h>

#import "CDZQRScanningViewController.h"

#ifndef CDZWeakSelf
#define CDZWeakSelf __weak __typeof__((__typeof__(self))self)
#endif

#ifndef CDZStrongSelf
#define CDZStrongSelf __typeof__(self)
#endif

static UIInterfaceOrientation CDZCurrentInterfaceOrientation() {
    return [[UIApplication performSelector:@selector(sharedApplication)] statusBarOrientation];
}

static AVCaptureVideoOrientation CDZVideoOrientationFromInterfaceOrientation(UIInterfaceOrientation interfaceOrientation) {
    switch (interfaceOrientation) {
#ifdef __IPHONE_8_0
        case UIInterfaceOrientationUnknown:
#endif
        case UIInterfaceOrientationPortrait:
            return AVCaptureVideoOrientationPortrait;
            break;
        case UIInterfaceOrientationLandscapeLeft:
            return AVCaptureVideoOrientationLandscapeLeft;
            break;
        case UIInterfaceOrientationLandscapeRight:
            return AVCaptureVideoOrientationLandscapeRight;
            break;
        case UIInterfaceOrientationPortraitUpsideDown:
            return AVCaptureVideoOrientationPortraitUpsideDown;
            break;
    }
}

static const float CDZQRScanningTorchLevel = 0.25;

NSString * const CDZQRScanningErrorDomain = @"com.cdzombak.qrscanningviewcontroller";

@interface CDZQRScanningViewController () <AVCaptureMetadataOutputObjectsDelegate>

@property (nonatomic, strong) AVCaptureSession *avSession;
@property (nonatomic, strong) AVCaptureDevice *captureDevice;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *previewLayer;
@property (nonatomic, strong) UIButton *torchButton;

@property (nonatomic, copy) NSString *lastCapturedString;

@property (nonatomic, strong, readwrite) NSArray *metadataObjectTypes;

@end

@implementation CDZQRScanningViewController

- (instancetype)initWithMetadataObjectTypes:(NSArray *)metadataObjectTypes {
    self = [super init];
    if (!self)
        return nil;
    
    self.metadataObjectTypes = metadataObjectTypes;
    self.title = NSLocalizedString(@"Scan QR Code", nil);
    
    UIImage *torchIcon = [UIImage imageNamed:@"CameraFlash.png"];
    
    CGRect bounds = CGRectMake(0, 0, 18.0f, torchIcon.size.height);
    UIGraphicsBeginImageContextWithOptions(bounds.size, NO, 0.0f);
    [torchIcon drawAtPoint:CGPointMake(CGRectGetMidX(bounds) - torchIcon.size.width / 2.0f, CGRectGetMidY(bounds) - torchIcon.size.height / 2.0f)];
    UIImage *buttonImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    UIButton *torchButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [torchButton setImage:buttonImage forState:UIControlStateNormal];
    [torchButton addTarget:self action:@selector(toggleTorch:) forControlEvents:UIControlEventTouchUpInside];
    torchButton.frame = CGRectMake(0, 0, buttonImage.size.width, buttonImage.size.height);
    _torchButton = torchButton;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:torchButton];
    
    return self;
}

- (instancetype)init {
    return [self initWithMetadataObjectTypes:@[ AVMetadataObjectTypeQRCode ]];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor blackColor];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    if (self.cancelBlock) {
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancelItemSelected:)];
    } else {
        self.navigationItem.leftBarButtonItem = nil;
    }

    self.lastCapturedString = nil;

    if (self.cancelBlock && !self.errorBlock) {
        CDZWeakSelf wSelf = self;
        self.errorBlock = ^(NSError *error) {
            CDZStrongSelf sSelf = wSelf;
            if (sSelf.cancelBlock) {
                [sSelf.avSession stopRunning];
                sSelf.cancelBlock();
            }
        };
    }

    self.avSession = [[AVCaptureSession alloc] init];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        self.captureDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
        if ([self.captureDevice isLowLightBoostSupported] && [self.captureDevice lockForConfiguration:nil]) {
            self.captureDevice.automaticallyEnablesLowLightBoostWhenAvailable = YES;
            [self.captureDevice unlockForConfiguration];
        }

        [self.avSession beginConfiguration];

        NSError *error = nil;
        AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:self.captureDevice error:&error];
        if (input) {
            [self.avSession addInput:input];
        } else {
            NSLog(@"QRScanningViewController: Error getting input device: %@", error);
            [self.avSession commitConfiguration];
            if (self.errorBlock) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self.avSession stopRunning];
                    self.errorBlock(error);
                });
            }
            return;
        }

        AVCaptureMetadataOutput *output = [[AVCaptureMetadataOutput alloc] init];
        [self.avSession addOutput:output];
        for (NSString *type in self.metadataObjectTypes) {
            if (![output.availableMetadataObjectTypes containsObject:type]) {
                if (self.errorBlock) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self.avSession stopRunning];
                        self.errorBlock([NSError errorWithDomain:CDZQRScanningErrorDomain code:CDZQRScanningViewControllerErrorUnavailableMetadataObjectType userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"Unable to scan object of type %@", type]}]);
                    });
                }
                return;
            }
        }

        output.metadataObjectTypes = self.metadataObjectTypes;
        [output setMetadataObjectsDelegate:self queue:dispatch_get_main_queue()];

        [self.avSession commitConfiguration];

        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.previewLayer.connection.isVideoOrientationSupported) {
                self.previewLayer.connection.videoOrientation = CDZVideoOrientationFromInterfaceOrientation(CDZCurrentInterfaceOrientation());
            }

            [self.avSession startRunning];
        });
    });

    self.previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:self.avSession];
    self.previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    self.previewLayer.frame = self.view.bounds;
    [self.view.layer addSublayer:self.previewLayer];
    
    UITapGestureRecognizer *gestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleFocusTap:)];
    [self.view addGestureRecognizer:gestureRecognizer];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];

    [self.previewLayer removeFromSuperlayer];
    self.previewLayer = nil;
    [self.avSession stopRunning];
    self.avSession = nil;
    self.captureDevice = nil;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGRect layerRect = self.view.bounds;
    self.previewLayer.bounds = layerRect;
    self.previewLayer.position = CGPointMake(CGRectGetMidX(layerRect), CGRectGetMidY(layerRect));

    if (self.previewLayer.connection.isVideoOrientationSupported) {
        self.previewLayer.connection.videoOrientation = CDZVideoOrientationFromInterfaceOrientation(CDZCurrentInterfaceOrientation());
    }
}

#pragma mark - UI Actions

- (void)cancelItemSelected:(id)sender {
    [self.avSession stopRunning];
    if (self.cancelBlock)
        self.cancelBlock();
}

- (void)toggleTorch:(id)sender {
    if (self.captureDevice.torchActive) {
        [self turnTorchOff];
        self.torchButton.selected = NO;
    } else {
        [self turnTorchOn];
        self.torchButton.selected = YES;
    }
}

- (void)handleFocusTap:(UIGestureRecognizer *)gestureRecognizer {
    CGPoint locationInView = [gestureRecognizer locationInView:self.view];
    CGPoint locationInCaptureDevice = [self.previewLayer captureDevicePointOfInterestForPoint:locationInView];
    
    AVCaptureDevice *captureDevice = self.captureDevice;
    NSError *error = nil;
    
    if ([captureDevice lockForConfiguration:&error]) {
        if ([captureDevice isFocusPointOfInterestSupported] && [captureDevice isFocusModeSupported:AVCaptureFocusModeAutoFocus]) {
            [captureDevice setFocusMode:AVCaptureFocusModeAutoFocus];
            [captureDevice setFocusPointOfInterest:locationInCaptureDevice];
        }
        
        if ([captureDevice isExposurePointOfInterestSupported] && [captureDevice isExposureModeSupported:AVCaptureExposureModeAutoExpose]) {
            [captureDevice setExposureMode:AVCaptureExposureModeAutoExpose];
            [captureDevice setExposurePointOfInterest:locationInCaptureDevice];
        }
        
        [captureDevice unlockForConfiguration];
        
    } else {
        NSLog(@"Capture device configuration error: %@", error);
    }
}

#pragma mark - Torch

- (void)turnTorchOn {
    if (self.captureDevice.hasTorch && self.captureDevice.torchAvailable && [self.captureDevice isTorchModeSupported:AVCaptureTorchModeOn] && [self.captureDevice lockForConfiguration:nil]) {
        [self.captureDevice setTorchModeOnWithLevel:CDZQRScanningTorchLevel error:nil];
        [self.captureDevice unlockForConfiguration];
    }
}

- (void)turnTorchOff {
    if (self.captureDevice.hasTorch && [self.captureDevice isTorchModeSupported:AVCaptureTorchModeOff] && [self.captureDevice lockForConfiguration:nil]) {
        self.captureDevice.torchMode = AVCaptureTorchModeOff;
        [self.captureDevice unlockForConfiguration];
    }
}

#pragma mark - AVCaptureMetadataOutputObjectsDelegate

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputMetadataObjects:(NSArray *)metadataObjects fromConnection:(AVCaptureConnection *)connection {
    NSString *stringResult = nil;
    AVMetadataMachineReadableCodeObject *result = nil;

    for (AVMetadataObject *metadata in metadataObjects) {
        if ([self.metadataObjectTypes containsObject:metadata.type]) {
            result = (AVMetadataMachineReadableCodeObject *)metadata;
            stringResult = [result stringValue];
            break;
        }
    }

    if (stringResult && ![self.lastCapturedString isEqualToString:stringResult]) {
        self.lastCapturedString = stringResult;
        [self.avSession stopRunning];
        if (self.resultBlock) self.resultBlock(result);
    }
}

@end

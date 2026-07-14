#import "RootViewController.h"
#import <ffmpegkit/FFmpegKit.h>
#import <PhotosUI/PhotosUI.h>
#import <MobileCoreServices/MobileCoreServices.h>

@interface RootViewController () <PHPickerViewControllerDelegate>

@property (nonatomic, assign) float currentScale;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UIViewController *swiftUIController;

@end

@implementation RootViewController

- (BOOL)shouldAutorotate {
    return NO;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskPortrait; 
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
    return UIInterfaceOrientationPortrait;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // ตั้งค่าพื้นหลังรวมเป็นสีดำสนิทสนมกับ Dark Mode 
    self.view.backgroundColor = [UIColor blackColor];
    self.currentScale = 2.0f; // ค่าเริ่มต้นของ itsscale
    
    if (self.navigationController) {
        self.navigationController.navigationBarHidden = NO;
        self.navigationController.navigationBar.barStyle = UIBarStyleBlack;
        self.navigationController.navigationBar.tintColor = [UIColor systemBlueColor];
        self.title = @"TT-Tool";
    }

    // [เปลี่ยนจุดนี้] จากเดิม "MainViewWrapper" เป็น "SwiftViewFactory" เพื่อให้ตรงกับโครงสร้าง Factory ใหม่
    Class wrapperClass = NSClassFromString(@"SwiftViewFactory");
    if (wrapperClass) {
        __weak typeof(self) weakSelf = self;
        
        void (^videoSelectionHandler)(void) = ^{
            [weakSelf openSystemPicker];
        };
        
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        self.swiftUIController = [wrapperClass performSelector:NSSelectorFromString(@"createMainViewWithOnSelectVideo:") withObject:videoSelectionHandler];
        #pragma clang diagnostic pop
        
        if (self.swiftUIController) {
            [self addChildViewController:self.swiftUIController];
            self.swiftUIController.view.frame = self.view.bounds;
            [self.view addSubview:self.swiftUIController.view];
            [self.swiftUIController didMoveToParentViewController:self];
        }
    }

    [self setupSpinner];
}

- (void)setupSpinner {
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    self.spinner.color = [UIColor systemBlueColor];
    self.spinner.center = self.view.center;
    self.spinner.hidesWhenStopped = YES;
    [self.view addSubview:self.spinner];
}

#pragma mark - Core Action: ดึงไฟล์ดิบผ่าน PHPicker (เลี่ยง WebKit Auto-Compress)

- (void)openSystemPicker {
    PHPickerConfiguration *config = [[PHPickerConfiguration alloc] initWithPhotoLibrary:[PHPhotoLibrary sharedPhotoLibrary]];
    config.filter = [PHPickerFilter videosFilter];
    config.preferredAssetRepresentationMode = PHPickerConfigurationAssetRepresentationModeCurrent; // จุดสำคัญ: ดึงไฟล์ดิบ ไม่แปลงไฟล์!
    
    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:config];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

#pragma mark - PHPickerViewControllerDelegate

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:nil];
    
    if (results.count == 0) return;
    
    [self.spinner startAnimating];
    
    PHPickerResult *result = results.firstObject;
    NSItemProvider *provider = result.itemProvider;
    
    // ดึง Type Identifier ของไฟล์วิดีโอต้นฉบับ
    NSString *typeIdentifier = @"public.mpeg-4";
    if (![provider hasItemConformingToTypeIdentifier:typeIdentifier]) {
        if (provider.registeredTypeIdentifiers.count > 0) {
            typeIdentifier = provider.registeredTypeIdentifiers.firstObject;
        }
    }
    
    [provider loadFileRepresentationForTypeIdentifier:typeIdentifier completionHandler:^(NSURL * _Nullable url, NSError * _Nullable error) {
        if (error || !url) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.spinner stopAnimating];
                [self showStatusAlert:@"เกิดข้อผิดพลาดในการดึงไฟล์ต้นฉบับ"];
            });
            return;
        }
        
        // คัดลอกวิดีโอไปยังตำแหน่งโฟลเดอร์ชั่วคราวของตัวแอป
        NSString *tempDir = NSTemporaryDirectory();
        // [แก้ไข] ปรับมาใช้ชื่อไฟล์ตาม วันเดือนปีชั่วโมงนาทีวินาที (yyMMddHHmmss) เพื่อแก้บัค File Lock รอบที่สอง
        NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
        [dateFormatter setDateFormat:@"yyMMddHHmmss"];
        NSString *timeStamp = [dateFormatter stringFromDate:[NSDate date]];
        
        @try {
            NSString *inputPath = [tempDir stringByAppendingPathComponent:[NSString stringWithFormat:@"Input_%@.MP4", timeStamp]];
            NSString *outputPath = [tempDir stringByAppendingPathComponent:[NSString stringWithFormat:@"Output_%@.MP4", timeStamp]];
            
            [[NSFileManager defaultManager] removeItemAtPath:inputPath error:nil];
            [[NSFileManager defaultManager] removeItemAtPath:outputPath error:nil];
            [[NSFileManager defaultManager] copyItemAtPath:url.path toPath:inputPath error:nil];
            
            // ประกอบคำสั่งและเริ่มประมวลผลผ่านคลัง FFmpegKit
            NSString *cmd = [NSString stringWithFormat:@"-itsscale %f -i %@ -codec copy %@", self.currentScale, inputPath, outputPath];
            
            [FFmpegKit executeAsync:cmd withCompleteCallback:^(id<Session> session) {
                ReturnCode *code = [session getReturnCode];
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self.spinner stopAnimating];
                    if ([ReturnCode isSuccess:code]) {
                        // ส่งวิดีโอผลลัพธ์กลับเข้าไปบันทึกไว้ในม้วนฟิล์มคลังภาพ
                        [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
                            [PHAssetChangeRequest creationRequestForAssetFromVideoAtFileURL:[NSURL fileURLWithPath:outputPath]];
                        } completionHandler:^(BOOL success, NSError * _Nullable error) {
                            
                            // ล้างและทำลายแคชไฟล์ขยะทั้งหมดใน Sandbox ทันทีเมื่อเสร็จสิ้นภารกิจ
                            [[NSFileManager defaultManager] removeItemAtPath:inputPath error:nil];
                            [[NSFileManager defaultManager] removeItemAtPath:outputPath error:nil];
                            
                            dispatch_async(dispatch_get_main_queue(), ^{
                                if (success) {
                                    [self showStatusAlert:@"แปลงไฟล์และบันทึกลงคลังภาพความละเอียด 1080p สำเร็จ!"];
                                } else {
                                    [self showStatusAlert:@"แปลงสำเร็จแต่บันทึกลงอัลบั้มไม่ได้ ตรวจสอบสิทธิ์เข้าถึงคลังภาพ"];
                                }
                            });
                        }];
                    } else {
                        // ล้างไฟล์ขยะหากเกิดเหตุการณ์รันล้มเหลว
                        [[NSFileManager defaultManager] removeItemAtPath:inputPath error:nil];
                        [[NSFileManager defaultManager] removeItemAtPath:outputPath error:nil];
                        [self showStatusAlert:@"คำสั่ง FFmpeg ทำงานล้มเหลว"];
                    }
                });
            }];
        } @catch (NSException *exception) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.spinner stopAnimating];
                [self showStatusAlert:@"เกิดข้อผิดพลาดภายในระบบไฟล์"];
            });
        }
    }];
}

- (void)showStatusAlert:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"ระบบทำงาน" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"ตากลบล็อค" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end

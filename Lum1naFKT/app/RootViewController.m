#import "RootViewController.h"
#import "KReader.h"
#import "ANEYcraft.h"

#import <notify.h>

@interface RootViewController ()
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, assign) BOOL dumping;
@end

@implementation RootViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Lum1naFKT";
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.navigationController.navigationBar.prefersLargeTitles = NO;

    UILabel *status = [UILabel new];
    status.translatesAutoresizingMaskIntoConstraints = NO;
    status.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    status.numberOfLines = 3;
    status.textColor = [UIColor secondaryLabelColor];
    status.text = @"0.8.0 ANE y-craft twin. KC scans copied kernelcache.";
    self.statusLabel = status;
    [self.view addSubview:status];

    UIStackView *row = [UIStackView new];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.axis = UILayoutConstraintAxisHorizontal;
    row.spacing = 8;
    row.distribution = UIStackViewDistributionFillEqually;

    UIButton *dumpBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [dumpBtn setTitle:@"Dump Now" forState:UIControlStateNormal];
    dumpBtn.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    dumpBtn.backgroundColor = [UIColor systemBlueColor];
    [dumpBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    dumpBtn.layer.cornerRadius = 10;
    [dumpBtn addTarget:self action:@selector(onDump) forControlEvents:UIControlEventTouchUpInside];

    UIButton *reloadBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [reloadBtn setTitle:@"Reload" forState:UIControlStateNormal];
    reloadBtn.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    reloadBtn.backgroundColor = [UIColor secondarySystemFillColor];
    [reloadBtn setTitleColor:[UIColor labelColor] forState:UIControlStateNormal];
    reloadBtn.layer.cornerRadius = 10;
    [reloadBtn addTarget:self action:@selector(onReload) forControlEvents:UIControlEventTouchUpInside];

    UIButton *copyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [copyBtn setTitle:@"Copy" forState:UIControlStateNormal];
    copyBtn.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    copyBtn.backgroundColor = [UIColor secondarySystemFillColor];
    [copyBtn setTitleColor:[UIColor labelColor] forState:UIControlStateNormal];
    copyBtn.layer.cornerRadius = 10;
    [copyBtn addTarget:self action:@selector(onCopy) forControlEvents:UIControlEventTouchUpInside];

    [row addArrangedSubview:dumpBtn];
    [row addArrangedSubview:reloadBtn];
    [row addArrangedSubview:copyBtn];
    [self.view addSubview:row];

    UIStackView *row2 = [UIStackView new];
    row2.translatesAutoresizingMaskIntoConstraints = NO;
    row2.axis = UILayoutConstraintAxisHorizontal;
    row2.spacing = 8;
    row2.distribution = UIStackViewDistributionFillEqually;

    UIButton *snapA = [UIButton buttonWithType:UIButtonTypeSystem];
    [snapA setTitle:@"Snap A" forState:UIControlStateNormal];
    snapA.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    snapA.backgroundColor = [UIColor systemIndigoColor];
    [snapA setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    snapA.layer.cornerRadius = 10;
    [snapA addTarget:self action:@selector(onSnapA) forControlEvents:UIControlEventTouchUpInside];

    UIButton *snapB = [UIButton buttonWithType:UIButtonTypeSystem];
    [snapB setTitle:@"Snap B" forState:UIControlStateNormal];
    snapB.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    snapB.backgroundColor = [UIColor systemIndigoColor];
    [snapB setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    snapB.layer.cornerRadius = 10;
    [snapB addTarget:self action:@selector(onSnapB) forControlEvents:UIControlEventTouchUpInside];

    UIButton *diffBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [diffBtn setTitle:@"Diff" forState:UIControlStateNormal];
    diffBtn.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    diffBtn.backgroundColor = [UIColor systemTealColor];
    [diffBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    diffBtn.layer.cornerRadius = 10;
    [diffBtn addTarget:self action:@selector(onDiff) forControlEvents:UIControlEventTouchUpInside];

    [row2 addArrangedSubview:snapA];
    [row2 addArrangedSubview:snapB];
    [row2 addArrangedSubview:diffBtn];
    [self.view addSubview:row2];

    // Row 3: Unlocked Primitives
    UIStackView *row3 = [UIStackView new];
    row3.translatesAutoresizingMaskIntoConstraints = NO;
    row3.axis = UILayoutConstraintAxisHorizontal;
    row3.spacing = 8;
    row3.distribution = UIStackViewDistributionFillEqually;

    UIButton *p005Btn = [UIButton buttonWithType:UIButtonTypeSystem];
    [p005Btn setTitle:@"P005 JIT" forState:UIControlStateNormal];
    p005Btn.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    p005Btn.backgroundColor = [UIColor systemPurpleColor];
    [p005Btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    p005Btn.layer.cornerRadius = 10;
    [p005Btn addTarget:self action:@selector(onP005) forControlEvents:UIControlEventTouchUpInside];

    UIButton *ioplBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [ioplBtn setTitle:@"65349 IOPL" forState:UIControlStateNormal];
    ioplBtn.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    ioplBtn.backgroundColor = [UIColor systemOrangeColor];
    [ioplBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    ioplBtn.layer.cornerRadius = 10;
    [ioplBtn addTarget:self action:@selector(onIOPL) forControlEvents:UIControlEventTouchUpInside];

    UIButton *aneBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [aneBtn setTitle:@"ANE Y-Craft" forState:UIControlStateNormal];
    aneBtn.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    aneBtn.backgroundColor = [UIColor systemRedColor];
    [aneBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    aneBtn.layer.cornerRadius = 10;
    [aneBtn addTarget:self action:@selector(onANEYcraft) forControlEvents:UIControlEventTouchUpInside];

    [row3 addArrangedSubview:p005Btn];
    [row3 addArrangedSubview:ioplBtn];
    [row3 addArrangedSubview:aneBtn];
    [self.view addSubview:row3];

    UITextView *tv = [UITextView new];
    tv.translatesAutoresizingMaskIntoConstraints = NO;
    tv.editable = NO;
    tv.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    tv.backgroundColor = [UIColor secondarySystemBackgroundColor];
    tv.textContainerInset = UIEdgeInsetsMake(10, 8, 10, 8);
    tv.alwaysBounceVertical = YES;
    self.textView = tv;
    [self.view addSubview:tv];

    UIActivityIndicatorView *spin =
        [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    spin.translatesAutoresizingMaskIntoConstraints = NO;
    spin.hidesWhenStopped = YES;
    self.spinner = spin;
    [self.view addSubview:spin];

    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [status.topAnchor constraintEqualToAnchor:g.topAnchor constant:8],
        [status.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:14],
        [status.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-14],

        [row.topAnchor constraintEqualToAnchor:status.bottomAnchor constant:10],
        [row.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:14],
        [row.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-14],
        [row.heightAnchor constraintEqualToConstant:44],

        [row2.topAnchor constraintEqualToAnchor:row.bottomAnchor constant:8],
        [row2.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:14],
        [row2.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-14],
        [row2.heightAnchor constraintEqualToConstant:44],

        [row3.topAnchor constraintEqualToAnchor:row2.bottomAnchor constant:8],
        [row3.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:14],
        [row3.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-14],
        [row3.heightAnchor constraintEqualToConstant:44],

        [tv.topAnchor constraintEqualToAnchor:row3.bottomAnchor constant:10],
        [tv.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:10],
        [tv.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-10],
        [tv.bottomAnchor constraintEqualToAnchor:g.bottomAnchor constant:-10],

        [spin.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [spin.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
    ]];

    self.navigationItem.leftBarButtonItems = @[
        [[UIBarButtonItem alloc] initWithTitle:@"Map"
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(onCatalog)],
        [[UIBarButtonItem alloc] initWithTitle:@"KC"
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(onKcScan)],
    ];
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"SB dump"
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(onSpringBoardNotify)];

    [self onReload];
}

- (void)setBusy:(BOOL)busy {
    self.dumping = busy;
    if (busy)
        [self.spinner startAnimating];
    else
        [self.spinner stopAnimating];
    self.view.userInteractionEnabled = !busy;
}

- (void)refreshStatus:(NSString *)extra {
    NSString *path = [KReader dumpPath];
    NSDictionary *attrs =
        [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    NSDate *mod = attrs[NSFileModificationDate];
    NSNumber *size = attrs[NSFileSize];
    NSString *modStr = mod ? [NSDateFormatter localizedStringFromDate:mod
                                                            dateStyle:NSDateFormatterShortStyle
                                                            timeStyle:NSDateFormatterMediumStyle]
                           : @"missing";
    NSString *sz = size ? [NSString stringWithFormat:@"%llu B", size.unsignedLongLongValue] : @"—";
    self.statusLabel.text = [NSString stringWithFormat:
        @"%@\n%@ · %@\n%@",
        extra ?: @"0.7.2 Primitive Lab · 21D50 twin (not 23F77 KVAs)",
        path, sz, modStr];
}

- (void)onReload {
    NSString *path = [KReader dumpPath];
    NSError *err = nil;
    NSString *body = [NSString stringWithContentsOfFile:path
                                               encoding:NSUTF8StringEncoding
                                                  error:&err];
    if (body.length) {
        self.textView.text = body;
        [self refreshStatus:@"loaded dump file"];
        [self.textView scrollRangeToVisible:NSMakeRange(0, 0)];
    } else {
        self.textView.text = [NSString stringWithFormat:
            @"(no dump yet)\npath: %@\n%@\n\nTap Dump Now.",
            path, err.localizedDescription ?: @""];
        [self refreshStatus:@"no dump file yet"];
    }
}

- (void)onCopy {
    NSString *t = self.textView.text ?: @"";
    if (!t.length) {
        [self refreshStatus:@"nothing to copy"];
        return;
    }
    [UIPasteboard generalPasteboard].string = t;
    [self refreshStatus:[NSString stringWithFormat:@"copied %lu chars", (unsigned long)t.length]];
}

- (void)onCatalog {
    NSString *cat = [KReader leftoverCatalog];
    self.textView.text = cat;
    [self refreshStatus:@"23F77 leftover catalog (no kread)"];
}

- (void)onKcScan {
    [self setBusy:YES];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *body = [KReader scanLocalKernelcache];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self setBusy:NO];
            self.textView.text = body;
            [self refreshStatus:@"KC file scan (mmap blob, not live 26.5)"];
        });
    });
}

- (void)onSpringBoardNotify {
    notify_post("com.lumina.fkt.dump");
    [self refreshStatus:@"posted com.lumina.fkt.dump — Reload in ~2s"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
                       [self onReload];
                   });
}

- (void)onSnapA {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *body = [KReader runSnapA];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.textView.text = body;
            [self refreshStatus:@"Snap A saved (PTR/SYSMEM/SHAPE/OCC)"];
        });
    });
}

- (void)onSnapB {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *body = [KReader runSnapB];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.textView.text = body;
            [self refreshStatus:@"Snap B saved"];
        });
    });
}

- (void)onDiff {
    NSString *body = [KReader runDiff];
    self.textView.text = body;
    [self refreshStatus:@"Diff A vs B (only_in_B = appeared)"];
}

- (void)onANEYcraft {
    [self setBusy:YES];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *body = [ANEYcraft run];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self setBusy:NO];
            self.textView.text = body;
            [self refreshStatus:@"ANE y-craft twin (see lum1na-fkt-ane.txt)"];
        });
    });
}

- (void)onP005 {
    [self setBusy:YES];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *body = [[KReader shared] runP005JITDowngrade];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self setBusy:NO];
            self.textView.text = body;
            [self refreshStatus:@"P005 JIT Downgrade Probe"];
        });
    });
}

- (void)onIOPL {
    [self setBusy:YES];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *body = [[KReader shared] run65349IOPLLeak];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self setBusy:NO];
            self.textView.text = body;
            [self refreshStatus:@"65349 IOPL OOB Probe"];
        });
    });
}

- (void)onDump {
    if (self.dumping)
        return;
    [self setBusy:YES];
    [self refreshStatus:@"dumping in-app…"];

    notify_post("com.lumina.fkt.dump");

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *body = [KReader runDumpPreferringRoot];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self setBusy:NO];
            if (body.length)
                self.textView.text = body;
            [self refreshStatus:@"dump done (root helper if needed) — Reload if stale"];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                               [self onReload];
                           });
        });
    });
}

@end
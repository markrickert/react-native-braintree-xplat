//
//  RCTBraintree.m
//  RCTBraintree
//
//  Created by Rickard Ekman on 18/06/16.
//  Modified by Mark Rickert to add ApplePay support on 12/10/17.
//  Copyright © 2016 Rickard Ekman. All rights reserved.
//  Copyright © 2017 Mark Rickert. All rights reserved.
//

#import "RCTBraintree.h"

@implementation RCTBraintree {
    bool runCallback;
}

static NSString *URLScheme;

+ (instancetype)sharedInstance {
    static RCTBraintree *_sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedInstance = [[RCTBraintree alloc] init];
    });
    return _sharedInstance;
}

- (instancetype)init
{
    if ((self = [super init])) {
        self.dataCollector = [[BTDataCollector alloc]
                              initWithEnvironment:BTDataCollectorEnvironmentProduction];
    }
    return self;
}

RCT_EXPORT_MODULE();

RCT_EXPORT_METHOD(setupWithURLScheme:(NSString *)clientToken urlscheme:(NSString*)urlscheme callback:(RCTResponseSenderBlock)callback)
{
    URLScheme = urlscheme;
    [BTAppSwitch setReturnURLScheme:urlscheme];
    self.braintreeClient = [[BTAPIClient alloc] initWithAuthorization:clientToken];
    if (self.braintreeClient == nil) {
        callback(@[@false]);
    }
    else {
        callback(@[@true]);
    }
}

RCT_EXPORT_METHOD(setup:(NSString *)clientToken callback:(RCTResponseSenderBlock)callback)
{
    self.braintreeClient = [[BTAPIClient alloc] initWithAuthorization:clientToken];
    if (self.braintreeClient == nil) {
        callback(@[@false]);
    }
    else {
        callback(@[@true]);
    }
}

RCT_EXPORT_METHOD(showPaymentViewController:(NSDictionary *)options callback:(RCTResponseSenderBlock)callback)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        BTDropInViewController *dropInViewController = [[BTDropInViewController alloc] initWithAPIClient:self.braintreeClient];
        dropInViewController.delegate = self;

        // NSLog(@"%@", options);

        UIColor *tintColor = options[@"tintColor"];
        UIColor *bgColor = options[@"bgColor"];
        UIColor *barBgColor = options[@"barBgColor"];
        UIColor *barTintColor = options[@"barTintColor"];

        NSString *title = options[@"title"];
        NSString *description = options[@"description"];
        NSString *amount = options[@"amount"];

        if (tintColor) dropInViewController.view.tintColor = [RCTConvert UIColor:tintColor];
        if (bgColor) dropInViewController.view.backgroundColor = [RCTConvert UIColor:bgColor];

        dropInViewController.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(userDidCancelPayment)];
        if (title) [dropInViewController.navigationItem setTitle:title];

        self.callback = callback;

        UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:dropInViewController];

        if (barBgColor) navigationController.navigationBar.barTintColor = [RCTConvert UIColor:barBgColor];
        if (barTintColor) navigationController.navigationBar.tintColor = [RCTConvert UIColor:barTintColor];

        if (options[@"callToActionText"]) {
            BTPaymentRequest *paymentRequest = [[BTPaymentRequest alloc] init];
            paymentRequest.callToActionText = options[@"callToActionText"];

            if (description) paymentRequest.summaryDescription = description;
            if (amount) paymentRequest.displayAmount = amount;

            dropInViewController.paymentRequest = paymentRequest;
        }

        [self.reactRoot presentViewController:navigationController animated:YES completion:nil];
    });
}

RCT_EXPORT_METHOD(showPayPalViewController:(RCTResponseSenderBlock)callback)
{
    dispatch_async(dispatch_get_main_queue(), ^{

        BTPayPalDriver *payPalDriver = [[BTPayPalDriver alloc] initWithAPIClient:self.braintreeClient];
        payPalDriver.viewControllerPresentingDelegate = self;

        [payPalDriver authorizeAccountWithCompletion:^(BTPayPalAccountNonce *tokenizedPayPalAccount, NSError *error) {
            NSMutableArray *args = @[[NSNull null]];
            if ( error == nil && tokenizedPayPalAccount != nil ) {
                args = [@[[NSNull null], tokenizedPayPalAccount.nonce, tokenizedPayPalAccount.email, tokenizedPayPalAccount.firstName, tokenizedPayPalAccount.lastName] mutableCopy];

                if (tokenizedPayPalAccount.phone != nil) {
                    [args addObject:tokenizedPayPalAccount.phone];
                }
            } else if ( error != nil ) {
                args = @[error.description, [NSNull null]];
            }

            callback(args);
        }];
    });
}

RCT_EXPORT_METHOD(getCardNonce: (NSDictionary *)parameters callback: (RCTResponseSenderBlock)callback)
{
    BTCardClient *cardClient = [[BTCardClient alloc] initWithAPIClient: self.braintreeClient];
    BTCard *card = [[BTCard alloc] initWithParameters:parameters];
    card.shouldValidate = YES;

    [cardClient tokenizeCard:card
                  completion:^(BTCardNonce *tokenizedCard, NSError *error) {
                      NSArray *args = @[];

                      if ( error == nil ) {
                          args = @[[NSNull null], tokenizedCard.nonce];
                      } else {
                          NSError *serialisationErr;
                          NSData *jsonData = [NSJSONSerialization dataWithJSONObject:[error userInfo]
                                                                             options:NSJSONWritingPrettyPrinted
                                                                               error:&serialisationErr];

                          if (! jsonData) {
                              args = @[serialisationErr.description, [NSNull null]];
                          } else {
                              NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
                              args = @[jsonString, [NSNull null]];
                          }
                      }

                      callback(args);
                  }];
}

RCT_EXPORT_METHOD(getDeviceData:(NSDictionary *)options callback:(RCTResponseSenderBlock)callback)
{
    dispatch_async(dispatch_get_main_queue(), ^{

        // NSLog(@"%@", options);

        NSError *error = nil;
        NSString *deviceData = nil;
        NSString *environment = options[@"environment"];
        NSString *dataSelector = options[@"dataCollector"];

        //Initialize the data collector and specify environment
        if([environment isEqualToString: @"development"]){
            self.dataCollector = [[BTDataCollector alloc]
                                  initWithEnvironment:BTDataCollectorEnvironmentDevelopment];
        } else if([environment isEqualToString: @"qa"]){
            self.dataCollector = [[BTDataCollector alloc]
                                  initWithEnvironment:BTDataCollectorEnvironmentQA];
        } else if([environment isEqualToString: @"sandbox"]){
            self.dataCollector = [[BTDataCollector alloc]
                                  initWithEnvironment:BTDataCollectorEnvironmentSandbox];
        }

        //Data collection methods
        if ([dataSelector isEqualToString: @"card"]){
            deviceData = [self.dataCollector collectCardFraudData];
        } else if ([dataSelector isEqualToString: @"both"]){
            deviceData = [self.dataCollector collectFraudData];
        } else if ([dataSelector isEqualToString: @"paypal"]){
            deviceData = [PPDataCollector collectPayPalDeviceData];
        } else {
            NSMutableDictionary* details = [NSMutableDictionary dictionary];
            [details setValue:@"Invalid data collector" forKey:NSLocalizedDescriptionKey];
            error = [NSError errorWithDomain:@"RCTBraintree" code:255 userInfo:details];
            NSLog (@"Invalid data collector. Use one of: card, paypal or both");
        }

        NSArray *args = @[];
        if ( error == nil ) {
            args = @[[NSNull null], deviceData];
        } else {
            args = @[error.description, [NSNull null]];
        }

        callback(args);
    });
}

RCT_EXPORT_METHOD(showApplePayViewController:(NSDictionary *)options callback:(RCTResponseSenderBlock)callback)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        self.callback = callback;

        PKPaymentRequest *paymentRequest = [[PKPaymentRequest alloc] init];

        paymentRequest.requiredBillingAddressFields = PKAddressFieldNone;
        paymentRequest.shippingMethods = nil;
        paymentRequest.requiredShippingAddressFields = PKAddressFieldNone;
        paymentRequest.paymentSummaryItems = [self getPaymentSummaryItemsFromDetails:options];
        paymentRequest.merchantIdentifier = options[@"merchantIdentifier"];;
        paymentRequest.supportedNetworks = @[PKPaymentNetworkVisa, PKPaymentNetworkMasterCard, PKPaymentNetworkAmex, PKPaymentNetworkDiscover];
        paymentRequest.merchantCapabilities = PKMerchantCapability3DS;
        paymentRequest.currencyCode = options[@"currencyCode"];
        paymentRequest.countryCode = options[@"countryCode"];
        if ([paymentRequest respondsToSelector:@selector(setShippingType:)]) {
            paymentRequest.shippingType = PKShippingTypeDelivery;
        }

        PKPaymentAuthorizationViewController *viewController = [[PKPaymentAuthorizationViewController alloc] initWithPaymentRequest:paymentRequest];
        viewController.delegate = self;

        [self.reactRoot presentViewController:viewController animated:YES completion:nil];
    });
}


- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication annotation:(id)annotation {

    if ([url.scheme localizedCaseInsensitiveCompare:URLScheme] == NSOrderedSame) {
        return [BTAppSwitch handleOpenURL:url sourceApplication:sourceApplication];
    }
    return NO;
}

#pragma mark - BTViewControllerPresentingDelegate

- (void)paymentDriver:(id)paymentDriver requestsPresentationOfViewController:(UIViewController *)viewController {
    [self.reactRoot presentViewController:viewController animated:YES completion:nil];
}

- (void)paymentDriver:(id)paymentDriver requestsDismissalOfViewController:(UIViewController *)viewController {
    if (!viewController.isBeingDismissed) {
        [viewController.presentingViewController dismissViewControllerAnimated:YES completion:nil];
    }
}

#pragma mark - BTDropInViewControllerDelegate

- (void)userDidCancelPayment {
    [self.reactRoot dismissViewControllerAnimated:YES completion:nil];
    self.callback(@[@"USER_CANCELLATION", [NSNull null]]);
}

- (void)dropInViewControllerWillComplete:(BTDropInViewController *)viewController {
    runCallback = TRUE;
}

- (void)dropInViewController:(BTDropInViewController *)viewController didSucceedWithTokenization:(BTPaymentMethodNonce *)paymentMethodNonce {
    // when the user pays for the first time with paypal, dropInViewControllerWillComplete is never called, yet the callback should be invoked.  the second condition checks for that
    if (runCallback || ([paymentMethodNonce.type isEqualToString:@"PayPal"] && [viewController.paymentMethodNonces count] == 1)) {
        runCallback = FALSE;
        self.callback(@[[NSNull null], @{
            @"nonce": paymentMethodNonce.nonce,
            @"type": paymentMethodNonce.type,
            @"localizedDescription": paymentMethodNonce.localizedDescription
        }]);
    }
    [self.reactRoot dismissViewControllerAnimated:YES completion:nil];
}

- (void)dropInViewControllerDidCancel:(__unused BTDropInViewController *)viewController {
    self.callback(@[@"Drop-In ViewController Closed", [NSNull null]]);
    [viewController dismissViewControllerAnimated:YES completion:nil];
}

- (UIViewController*)reactRoot {
    UIViewController *root  = [UIApplication sharedApplication].keyWindow.rootViewController;
    UIViewController *maybeModal = root.presentedViewController;

    UIViewController *modalRoot = root;

    if (maybeModal != nil) {
        modalRoot = maybeModal;
    }

    return modalRoot;
}

#pragma mark PKPaymentAuthorizationViewControllerDelegate

- (void)paymentAuthorizationViewController:(__unused PKPaymentAuthorizationViewController *)controller
                       didAuthorizePayment:(PKPayment *)payment
                                completion:(void (^)(PKPaymentAuthorizationStatus status))completion
{
    BTApplePayClient *applePayClient = [[BTApplePayClient alloc] initWithAPIClient:self.braintreeClient];
    [applePayClient tokenizeApplePayPayment:payment completion:^(BTApplePayCardNonce * _Nullable tokenizedApplePayPayment, NSError * _Nullable error) {
        if (error) {
            completion(PKPaymentAuthorizationStatusFailure);
            self.callback(@[@"Error processing card", [NSNull null]]);
        } else {
            self.callback(@[[NSNull null], @{
                                @"nonce": tokenizedApplePayPayment.nonce,
                                @"type": tokenizedApplePayPayment.type,
                                @"localizedDescription": tokenizedApplePayPayment.localizedDescription
            }]);

            completion(PKPaymentAuthorizationStatusSuccess);
        }
    }];
}


- (void)paymentAuthorizationViewControllerDidFinish:(PKPaymentAuthorizationViewController *)controller {
    // Just close the view controller. We either succeeded or the user hit cancel.
    [self.reactRoot dismissViewControllerAnimated:YES completion:nil];
}

- (void)paymentAuthorizationViewControllerWillAuthorizePayment:(PKPaymentAuthorizationViewController *)controller {
    // Move along. Nothing to see here.
}

// Helper function to convert our details to PKPaymentSummaryItems
- (NSArray<PKPaymentSummaryItem *> *_Nonnull)getPaymentSummaryItemsFromDetails:(NSDictionary *_Nonnull)details
{
    // Setup `paymentSummaryItems` array
    NSMutableArray <PKPaymentSummaryItem *> * paymentSummaryItems = [NSMutableArray array];

    // Add `displayItems` to `paymentSummaryItems`
    NSArray *displayItems = details[@"displayItems"];
    if (displayItems.count > 0) {
        for (NSDictionary *displayItem in displayItems) {
            [paymentSummaryItems addObject: [self convertDisplayItemToPaymentSummaryItem:displayItem]];
        }
    }

    // Add shipping to `paymentSummaryItems`
    if([details objectForKey:@"shipping"]) {
        NSDictionary *shipping = details[@"shipping"];
        [paymentSummaryItems addObject: [self convertDisplayItemToPaymentSummaryItem:shipping]];
    }

    // Add total to `paymentSummaryItems`
    NSDictionary *total = details[@"total"];
    [paymentSummaryItems addObject: [self convertDisplayItemToPaymentSummaryItem:total]];

    return paymentSummaryItems;
}

- (PKPaymentSummaryItem *_Nonnull)convertDisplayItemToPaymentSummaryItem:(NSDictionary *_Nonnull)displayItem;
{
    NSDecimalNumber *decimalNumberAmount = [NSDecimalNumber decimalNumberWithString:displayItem[@"amount"]];
    PKPaymentSummaryItem *paymentSummaryItem = [PKPaymentSummaryItem summaryItemWithLabel:displayItem[@"label"] amount:decimalNumberAmount];

    return paymentSummaryItem;
}

@end

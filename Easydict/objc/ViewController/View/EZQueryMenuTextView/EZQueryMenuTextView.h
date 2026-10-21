//
//  EZQueryMenuTextView.h
//  Easydict
//
//  Created by tisfeng on 2023/10/17.
//  Copyright © 2023 izual. All rights reserved.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface EZQueryMenuTextView : NSTextView

- (void)queryInApp:(id)sender;

/// Reuses the configured selection-lookup window routing for native and web-rendered text.
+ (void)queryTextInApp:(NSString *)text NS_SWIFT_NAME(queryInApp(_:));

@end

NS_ASSUME_NONNULL_END

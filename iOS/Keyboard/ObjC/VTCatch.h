// Bắt NSException từ UIKit mà Swift không bắt được (crash 28/09/2026, iOS 27.0:
// -[_UITextDocumentInterface keyboardType] → _controllerState unrecognized selector
// ngay trong viewWillAppear ⇒ bàn phím chết, iOS quay về bàn phím gốc).
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Chạy `block`; nếu block ném NSException thì nuốt lỗi và trả về exception đó.
FOUNDATION_EXPORT NSException * _Nullable VTCatchException(NS_NOESCAPE void (^block)(void));

NS_ASSUME_NONNULL_END

#import <Foundation/Foundation.h>
#import "StoryState.h"

NS_ASSUME_NONNULL_BEGIN

@interface StoryEngine : NSObject

@property (nonatomic, strong, readonly) NSDictionary *content;
@property (nonatomic, strong, readonly) StoryState *state;
@property (nonatomic, strong, readonly, nullable) NSDictionary *currentNode;

- (instancetype)initWithSavedState:(nullable NSDictionary *)savedState error:(NSError **)error;
- (void)startNewGame;
- (nullable NSDictionary *)advance;
- (nullable NSDictionary *)selectChoiceAtIndex:(NSInteger)index;
- (BOOL)isCurrentNodeRead;
- (nullable NSDictionary *)alreadyReadChoiceAfterCurrentNode;
- (BOOL)hiddenEndingRequirementsMet;
- (BOOL)rewindToLatestCheckpoint;
- (BOOL)rewindToCheckpointAtIndex:(NSInteger)index;
- (NSArray<NSDictionary *> *)availableCheckpoints;
- (NSDictionary *)savePayload;
- (NSArray<NSString *> *)validationErrors;

@end

NS_ASSUME_NONNULL_END

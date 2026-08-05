#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface StoryState : NSObject

@property (nonatomic, copy) NSString *currentNodeID;
@property (nonatomic, strong, readonly) NSMutableDictionary<NSString *, NSNumber *> *variables;
@property (nonatomic, strong, readonly) NSMutableSet<NSString *> *clues;
@property (nonatomic, strong, readonly) NSMutableDictionary<NSString *, NSString *> *choices;
@property (nonatomic, strong, readonly) NSMutableSet<NSString *> *readNodeIDs;
@property (nonatomic, strong, readonly) NSMutableArray<NSDictionary *> *dialogueLog;
@property (nonatomic, strong, readonly) NSMutableArray<NSDictionary *> *checkpoints;

- (instancetype)initWithStartNodeID:(NSString *)startNodeID;
- (instancetype)initWithDictionary:(NSDictionary *)dictionary startNodeID:(NSString *)startNodeID;
- (void)applyEffects:(NSArray<NSDictionary *> *)effects;
- (NSDictionary *)dictionaryRepresentation;
- (NSDictionary *)snapshot;
- (void)restoreSnapshot:(NSDictionary *)snapshot;

@end

NS_ASSUME_NONNULL_END

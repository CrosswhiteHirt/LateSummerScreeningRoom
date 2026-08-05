#import "StoryState.h"

@implementation StoryState

- (instancetype)initWithStartNodeID:(NSString *)startNodeID {
    return [self initWithDictionary:@{} startNodeID:startNodeID];
}

- (instancetype)initWithDictionary:(NSDictionary *)dictionary startNodeID:(NSString *)startNodeID {
    self = [super init];
    if (self) {
        _currentNodeID = [dictionary[@"currentNodeID"] isKindOfClass:[NSString class]] ? dictionary[@"currentNodeID"] : startNodeID;
        NSDictionary *savedVariables = [dictionary[@"variables"] isKindOfClass:[NSDictionary class]] ? dictionary[@"variables"] : @{};
        _variables = [@{ @"FaceTruth": @0, @"TrustFriends": @0, @"EmpathyChinatsu": @0 } mutableCopy];
        [_variables addEntriesFromDictionary:savedVariables];
        _clues = [NSMutableSet setWithArray:[dictionary[@"clues"] isKindOfClass:[NSArray class]] ? dictionary[@"clues"] : @[]];
        _choices = [([dictionary[@"choices"] isKindOfClass:[NSDictionary class]] ? dictionary[@"choices"] : @{}) mutableCopy];
        _readNodeIDs = [NSMutableSet setWithArray:[dictionary[@"readNodeIDs"] isKindOfClass:[NSArray class]] ? dictionary[@"readNodeIDs"] : @[]];
        _dialogueLog = [([dictionary[@"dialogueLog"] isKindOfClass:[NSArray class]] ? dictionary[@"dialogueLog"] : @[]) mutableCopy];
        _checkpoints = [([dictionary[@"checkpoints"] isKindOfClass:[NSArray class]] ? dictionary[@"checkpoints"] : @[]) mutableCopy];
    }
    return self;
}

- (void)applyEffects:(NSArray<NSDictionary *> *)effects {
    for (NSDictionary *effect in effects) {
        NSString *kind = effect[@"kind"];
        NSString *key = effect[@"key"];
        if ([kind isEqualToString:@"variable"] && key.length > 0) {
            NSInteger value = [self.variables[key] integerValue] + [effect[@"delta"] integerValue];
            self.variables[key] = @(value);
        } else if ([kind isEqualToString:@"clue"] && key.length > 0 && [effect[@"value"] boolValue]) {
            [self.clues addObject:key];
        }
    }
}

- (NSDictionary *)snapshot {
    return @{
        @"currentNodeID": self.currentNodeID ?: @"",
        @"variables": [self.variables copy],
        @"clues": self.clues.allObjects,
        @"choices": [self.choices copy],
        @"dialogueLog": [self.dialogueLog copy]
    };
}

- (void)restoreSnapshot:(NSDictionary *)snapshot {
    self.currentNodeID = snapshot[@"currentNodeID"] ?: self.currentNodeID;
    [self.variables removeAllObjects];
    [self.variables addEntriesFromDictionary:snapshot[@"variables"] ?: @{}];
    [self.clues removeAllObjects];
    [self.clues addObjectsFromArray:snapshot[@"clues"] ?: @[]];
    [self.choices removeAllObjects];
    [self.choices addEntriesFromDictionary:snapshot[@"choices"] ?: @{}];
    // Dialogue history is a log, not branch state: rewinding must not discard
    // records that the player has already seen.
}

- (NSDictionary *)dictionaryRepresentation {
    NSMutableDictionary *result = [[self snapshot] mutableCopy];
    result[@"readNodeIDs"] = self.readNodeIDs.allObjects;
    result[@"checkpoints"] = [self.checkpoints copy];
    return result;
}

@end

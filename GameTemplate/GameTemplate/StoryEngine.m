#import "StoryEngine.h"

@interface StoryEngine ()
@property (nonatomic, strong, readwrite) NSDictionary *content;
@property (nonatomic, strong, readwrite) StoryState *state;
@end

@implementation StoryEngine

- (instancetype)initWithSavedState:(NSDictionary *)savedState error:(NSError **)error {
    self = [super init];
    if (!self) { return nil; }
    NSURL *url = [[NSBundle mainBundle] URLForResource:@"StoryContent" withExtension:@"json"];
    NSData *data = url ? [NSData dataWithContentsOfURL:url] : nil;
    NSDictionary *content = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:error] : nil;
    if (![content isKindOfClass:[NSDictionary class]]) {
        if (error && !*error) {
            *error = [NSError errorWithDomain:@"LateSummer.Story" code:1 userInfo:@{NSLocalizedDescriptionKey: @"StoryContent.json is missing or invalid."}];
        }
        return nil;
    }
    _content = content;
    _state = [[StoryState alloc] initWithDictionary:savedState ?: @{} startNodeID:content[@"startNodeID"]];
    if (![content[@"nodes"] objectForKey:_state.currentNodeID]) {
        _state.currentNodeID = content[@"startNodeID"];
    }
    return self;
}

- (NSDictionary *)currentNode {
    return self.content[@"nodes"][self.state.currentNodeID];
}

- (void)startNewGame {
    self.state = [[StoryState alloc] initWithStartNodeID:self.content[@"startNodeID"]];
    [self registerCurrentNode];
}

- (void)registerCurrentNode {
    NSDictionary *node = self.currentNode;
    if (!node) { return; }
    [self.state applyEffects:node[@"effects"] ?: @[]];
    [self.state.readNodeIDs addObject:self.state.currentNodeID];
    if ([node[@"checkpoint"] boolValue]) {
        NSString *existingID = [self.state.checkpoints.lastObject objectForKey:@"nodeID"];
        if (![existingID isEqualToString:self.state.currentNodeID]) {
            NSDictionary *entry = @{
                @"nodeID": self.state.currentNodeID,
                @"title": node[@"text"] ?: node[@"scene"] ?: @"Checkpoint",
                @"snapshot": [self.state snapshot]
            };
            [self.state.checkpoints addObject:entry];
            if (self.state.checkpoints.count > 20) {
                [self.state.checkpoints removeObjectAtIndex:0];
            }
        }
    }
}

- (NSString *)resolvedNextForNode:(NSDictionary *)node {
    NSDictionary *conditional = node[@"conditionalNext"];
    if ([conditional[@"requiresHidden"] boolValue]) {
        return [self hiddenEndingRequirementsMet] ? conditional[@"target"] : conditional[@"fallback"];
    }
    return node[@"next"];
}

- (NSDictionary *)advance {
    NSDictionary *node = self.currentNode;
    NSString *next = [self resolvedNextForNode:node];
    if (next.length == 0) { return nil; }
    self.state.currentNodeID = next;
    [self registerCurrentNode];
    return self.currentNode;
}

- (NSDictionary *)selectChoiceAtIndex:(NSInteger)index {
    NSArray *options = self.currentNode[@"options"];
    if (index < 0 || index >= (NSInteger)options.count) { return nil; }
    NSDictionary *option = options[index];
    [self.state applyEffects:option[@"effects"] ?: @[]];
    NSString *choiceID = option[@"id"];
    if (choiceID.length > 0) { self.state.choices[choiceID] = option[@"text"] ?: @""; }
    self.state.currentNodeID = option[@"target"];
    [self registerCurrentNode];
    return self.currentNode;
}

- (BOOL)isCurrentNodeRead {
    return [self.state.readNodeIDs containsObject:self.state.currentNodeID];
}

- (NSDictionary *)alreadyReadChoiceAfterCurrentNode {
    NSDictionary *node = self.currentNode;
    NSString *nodeID = self.state.currentNodeID;
    for (NSInteger step = 0; step < 1000 && node; step++) {
        NSString *type = node[@"type"];
        if ([type isEqualToString:@"choice"] || [type isEqualToString:@"ending"]) {
            if ([type isEqualToString:@"choice"] && [self.state.readNodeIDs containsObject:nodeID]) {
                return node;
            }
            return nil;
        }
        NSString *nextID = [self resolvedNextForNode:node];
        if (nextID.length == 0) { return nil; }
        nodeID = nextID;
        node = self.content[@"nodes"][nodeID];
    }
    return nil;
}

- (BOOL)hiddenEndingRequirementsMet {
    NSDictionary *rules = self.content[@"hiddenEnding"];
    for (NSString *clue in rules[@"requiredClues"]) {
        if (![self.state.clues containsObject:clue]) { return NO; }
    }
    for (NSString *key in rules[@"thresholds"]) {
        if ([self.state.variables[key] integerValue] < [rules[@"thresholds"][key] integerValue]) { return NO; }
    }
    return YES;
}

- (NSArray<NSDictionary *> *)availableCheckpoints {
    return [self.state.checkpoints copy];
}

- (BOOL)rewindToLatestCheckpoint {
    if (self.state.checkpoints.count < 2) { return NO; }
    return [self rewindToCheckpointAtIndex:self.state.checkpoints.count - 2];
}

- (BOOL)rewindToCheckpointAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.state.checkpoints.count) { return NO; }
    NSDictionary *checkpoint = self.state.checkpoints[index];
    NSArray *retained = [self.state.checkpoints subarrayWithRange:NSMakeRange(0, index + 1)];
    [self.state restoreSnapshot:checkpoint[@"snapshot"]];
    [self.state.checkpoints removeAllObjects];
    [self.state.checkpoints addObjectsFromArray:retained];
    return self.currentNode != nil;
}

- (NSDictionary *)savePayload {
    return @{ @"schemaVersion": @2, @"savedAt": @([[NSDate date] timeIntervalSince1970]), @"state": [self.state dictionaryRepresentation] };
}

- (NSArray<NSString *> *)validationErrors {
    NSMutableArray<NSString *> *errors = [NSMutableArray array];
    NSDictionary *nodes = self.content[@"nodes"];
    if (!nodes[self.content[@"startNodeID"]]) { [errors addObject:@"Missing start node"]; }
    [nodes enumerateKeysAndObjectsUsingBlock:^(NSString *nodeID, NSDictionary *node, BOOL *stop) {
        NSMutableArray *targets = [NSMutableArray array];
        if (node[@"next"]) { [targets addObject:node[@"next"]]; }
        for (NSDictionary *option in node[@"options"] ?: @[]) { if (option[@"target"]) [targets addObject:option[@"target"]]; }
        NSDictionary *conditional = node[@"conditionalNext"];
        if (conditional[@"target"]) [targets addObject:conditional[@"target"]];
        if (conditional[@"fallback"]) [targets addObject:conditional[@"fallback"]];
        for (NSString *target in targets) {
            if (!nodes[target]) [errors addObject:[NSString stringWithFormat:@"%@ -> missing %@", nodeID, target]];
        }
    }];
    return errors;
}

@end

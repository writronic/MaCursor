
#import <Foundation/Foundation.h>

@interface GBSettings : NSObject

#pragma mark - Initialization & disposal

+ (id)settingsWithName:(NSString *)name parent:(GBSettings *)parent;
- (id)initWithName:(NSString *)name parent:(GBSettings *)parent;

#pragma mark - Settings serialization support

- (BOOL)loadSettingsFromPlist:(NSString *)path error:(NSError **)error;
- (BOOL)saveSettingsToPlist:(NSString *)path error:(NSError **)error;

#pragma mark - Values handling

- (id)objectForKey:(NSString *)key;
- (void)setObject:(id)value forKey:(NSString *)key;

- (BOOL)boolForKey:(NSString *)key;
- (void)setBool:(BOOL)value forKey:(NSString *)key;

- (NSInteger)integerForKey:(NSString *)key;
- (void)setInteger:(NSInteger)value forKey:(NSString *)key;

- (NSUInteger)unsignedIntegerForKey:(NSString *)key;
- (void)setUnsignedInteger:(NSUInteger)value forKey:(NSString *)key;

- (CGFloat)floatForKey:(NSString *)key;
- (void)setFloat:(CGFloat)value forKey:(NSString *)key;

#pragma mark - Arguments handling

- (void)addArgument:(NSString *)argument;
- (GBSettings *)settingsForArgument:(NSString *)argument;
@property (nonatomic, strong) NSArray *arguments;

#pragma mark - Registration & low level handling

- (void)registerArrayForKey:(NSString *)key;
- (id)objectForLocalKey:(NSString *)key;
- (void)setObject:(id)value forLocalKey:(NSString *)key;

#pragma mark - Introspection

- (void)enumerateSettings:(void(^)(GBSettings *settings, BOOL *stop))handler;
- (GBSettings *)settingsForArrayValue:(NSString *)value key:(NSString *)key;
- (GBSettings *)settingsForKey:(NSString *)key;
- (BOOL)isKeyPresentAtThisLevel:(NSString *)key;
- (BOOL)isKeyArray:(NSString *)key;

#pragma mark - Properties

@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly, strong) GBSettings *parent;

@end

#pragma mark - Convenience one-line synthesize macros for concrete properties

#define GB_SYNTHESIZE_PROPERTY(type, accessorSel, mutatorSel, valueAccessor, valueMutator, key, val) \
	- (type)accessorSel { return [self valueAccessor:key]; } \
	- (void)mutatorSel:(type)value { [self valueMutator:val forKey:key]; }
#define GB_SYNTHESIZE_OBJECT(type, accessorSel, mutatorSel, key) GB_SYNTHESIZE_PROPERTY(type, accessorSel, mutatorSel, objectForKey, setObject, key, value)
#define GB_SYNTHESIZE_COPY(type, accessorSel, mutatorSel, key) GB_SYNTHESIZE_PROPERTY(type, accessorSel, mutatorSel, objectForKey, setObject, key, [value copy])
#define GB_SYNTHESIZE_BOOL(accessorSel, mutatorSel, key) GB_SYNTHESIZE_PROPERTY(BOOL, accessorSel, mutatorSel, boolForKey, setBool, key, value)
#define GB_SYNTHESIZE_INT(accessorSel, mutatorSel, key) GB_SYNTHESIZE_PROPERTY(NSInteger, accessorSel, mutatorSel, integerForKey, setInteger, key, value)
#define GB_SYNTHESIZE_UINT(accessorSel, mutatorSel, key) GB_SYNTHESIZE_PROPERTY(NSUInteger, accessorSel, mutatorSel, unsignedIntegerForKey, setUnsignedInteger, key, value)
#define GB_SYNTHESIZE_FLOAT(accessorSel, mutatorSel, key) GB_SYNTHESIZE_PROPERTY(CGFloat, accessorSel, mutatorSel, floatForKey, setFloat, key, value)

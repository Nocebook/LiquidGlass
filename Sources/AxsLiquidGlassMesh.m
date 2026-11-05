#import "AxsLiquidGlassMesh.h"
#import "AxsLiquidGlassLog.h"
#import "AxsLiquidGlassPrivate.h"

#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <stdlib.h>

static char kAxsMeshAppliedKey;
static char kAxsMeshOriginalKey;
static NSInteger gAxsMeshAppliedCount = 0;
static NSInteger gAxsMeshMissCount = 0;
static BOOL gAxsMeshLogged = NO;

#pragma mark - CAMeshTransform 运行时桥

// CAMeshTransform 是 QuartzCore 的私有类，SDK 里没有声明。
// 这里不引入符号，全部走 runtime，避免链接期找不到类、也避免写死结构体布局。
typedef struct {
    CGPoint position;   // 归一化坐标 0~1，相对图层 bounds
    double normal[3];   // CAPoint3D，平面形变时保持 0,0,0
} AxsMeshVertex;

typedef struct {
    unsigned int indices[4];
    float weights[4];
} AxsMeshFace;

typedef id (*AxsMeshTransformFn)(Class, SEL, NSUInteger, const void *, NSUInteger, const void *, id);

static id AxsCreateMeshTransform(NSUInteger vertexCount,
                                 const AxsMeshVertex *vertices,
                                 NSUInteger faceCount,
                                 const AxsMeshFace *faces) {
    Class cls = NSClassFromString(@"CAMeshTransform");
    if (!cls) return nil;
    SEL selector = NSSelectorFromString(@"meshTransformWithVertexCount:vertices:faceCount:faces:depthNormalization:");
    if (![cls respondsToSelector:selector]) return nil;
    AxsMeshTransformFn fn = (AxsMeshTransformFn)[cls methodForSelector:selector];
    if (!fn) return nil;
    @try {
        // depthNormalization 传 "none"：我们只做平面折弯，不需要深度归一化。
        return fn(cls, selector, vertexCount, vertices, faceCount, faces, @"none");
    } @catch (NSException *exception) {
        (void)exception;
        return nil;
    }
}

#pragma mark - 网格缓存

/// 同一个（宽、高、圆角、强度、档位）只生成一次网格。
/// 控制中心反复开关时，这一步能省掉 90% 的重复计算。
static NSCache<NSString *, id> *AxsMeshCache(void) {
    static NSCache<NSString *, id> *cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [[NSCache alloc] init];
        cache.countLimit = 24;
    });
    return cache;
}

static id AxsMeshForGeometry(CGFloat width, CGFloat height, CGFloat radius, double strength) {
    if (width < 1.0 || height < 1.0) return nil;

    NSString *key = [NSString stringWithFormat:@"%.0fx%.0f-%.0f-%.2f",
                     width, height, radius, strength];
    id cached = [AxsMeshCache() objectForKey:key];
    if (cached) return cached;

    // 网格密度：小卡片用 10 段，大面板用 8 段。144 个面的形变在 GPU 上是白送的，
    // 但没必要给全屏表面堆到 400 个面。
    NSInteger segments = (width * height > 260000.0) ? 8 : 10;
    NSInteger side = segments + 1;
    NSUInteger vertexCount = (NSUInteger)(side * side);
    NSUInteger faceCount = (NSUInteger)(segments * segments);

    AxsMeshVertex *vertices = calloc(vertexCount, sizeof(AxsMeshVertex));
    AxsMeshFace *faces = calloc(faceCount, sizeof(AxsMeshFace));
    if (!vertices || !faces) {
        free(vertices);
        free(faces);
        return nil;
    }

    // 折射带宽度跟着圆角走：圆角越大，边缘弯折的影响范围越宽。
    double bandX = AxsLiquidGlassClamp((double)radius / (double)width * 1.35, 0.05, 0.22);
    double bandY = AxsLiquidGlassClamp((double)radius / (double)height * 1.35, 0.05, 0.22);
    double push = AxsLiquidGlassClamp(strength, 0.0, 1.0) * 0.11;

    for (NSInteger row = 0; row < side; row++) {
        for (NSInteger column = 0; column < side; column++) {
            double u = (double)column / (double)segments;
            double v = (double)row / (double)segments;

            // 到最近一条边的归一化距离
            double distanceX = fmin(u, 1.0 - u);
            double distanceY = fmin(v, 1.0 - v);

            double tX = (distanceX < bandX) ? (1.0 - distanceX / bandX) : 0.0;
            double tY = (distanceY < bandY) ? (1.0 - distanceY / bandY) : 0.0;

            // 二次曲线：越靠近边线弯得越急，离开带区立刻归零，避免整块画面被拉花。
            double shiftX = push * tX * tX;
            double shiftY = push * tY * tY;

            double su = (u < 0.5) ? (u + shiftX) : (u - shiftX);
            double sv = (v < 0.5) ? (v + shiftY) : (v - shiftY);

            AxsMeshVertex *vertex = &vertices[row * side + column];
            vertex->position = CGPointMake(AxsLiquidGlassClamp(su, 0.0, 1.0),
                                           AxsLiquidGlassClamp(sv, 0.0, 1.0));
            vertex->normal[0] = 0.0;
            vertex->normal[1] = 0.0;
            vertex->normal[2] = 0.0;
        }
    }

    for (NSInteger row = 0; row < segments; row++) {
        for (NSInteger column = 0; column < segments; column++) {
            unsigned int topLeft = (unsigned int)(row * side + column);
            unsigned int topRight = topLeft + 1;
            unsigned int bottomLeft = (unsigned int)((row + 1) * side + column);
            unsigned int bottomRight = bottomLeft + 1;

            AxsMeshFace *face = &faces[row * segments + column];
            face->indices[0] = topLeft;
            face->indices[1] = topRight;
            face->indices[2] = bottomRight;
            face->indices[3] = bottomLeft;
            face->weights[0] = 1.0f;
            face->weights[1] = 1.0f;
            face->weights[2] = 1.0f;
            face->weights[3] = 1.0f;
        }
    }

    id mesh = AxsCreateMeshTransform(vertexCount, vertices, faceCount, faces);
    free(vertices);
    free(faces);

    if (mesh) [AxsMeshCache() setObject:mesh forKey:key];
    return mesh;
}

#pragma mark - 图层查找

static BOOL AxsLayerWantsRefraction(CALayer *layer) {
    Class backdropClass = NSClassFromString(@"CABackdropLayer");
    if (backdropClass && [layer isKindOfClass:backdropClass]) return YES;
    NSString *name = NSStringFromClass([layer class]);
    return [name containsString:@"BackdropLayer"];
}

/// 只往下找 4 层：UIVisualEffectView 的 backdrop 一般就在 1~2 层内，
/// 再深的属于内容层，误挂会把内容也折弯。
static CALayer *AxsFindBackdropLayer(CALayer *layer, NSInteger depth) {
    if (!layer || depth > 4) return nil;
    if (AxsLayerWantsRefraction(layer)) return layer;
    for (CALayer *sublayer in layer.sublayers) {
        CALayer *found = AxsFindBackdropLayer(sublayer, depth + 1);
        if (found) return found;
    }
    return nil;
}

static BOOL AxsSetMeshTransform(CALayer *layer, id mesh) {
    if (!layer) return NO;
    SEL selector = NSSelectorFromString(@"setMeshTransform:");
    if ([layer respondsToSelector:selector]) {
        void (*fn)(id, SEL, id) = (void (*)(id, SEL, id))[layer methodForSelector:selector];
        if (fn) {
            @try {
                fn(layer, selector, mesh);
                return YES;
            } @catch (NSException *exception) {
                (void)exception;
            }
        }
    }
    @try {
        [layer setValue:mesh forKey:@"meshTransform"];
        return YES;
    } @catch (NSException *exception) {
        (void)exception;
        return NO;
    }
}

@implementation AxsLiquidGlassMesh

+ (BOOL)axs_liquidglass_hasRefraction:(UIView *)view {
    return objc_getAssociatedObject(view, &kAxsMeshAppliedKey) != nil;
}

+ (BOOL)axs_liquidglass_applyRefractionToView:(UIView *)view
                                       radius:(CGFloat)radius
                                     strength:(double)strength
                                     perfMode:(NSInteger)perfMode {
    if (!view || !view.layer) return NO;
    if (![NSThread isMainThread]) return NO;
    if (strength <= 0.01 || perfMode <= 0) {
        [self axs_liquidglass_clearRefractionFromView:view];
        return NO;
    }

    CGRect bounds = view.bounds;
    CGFloat width = CGRectGetWidth(bounds);
    CGFloat height = CGRectGetHeight(bounds);
    if (width < 60.0 || height < 60.0 || radius < 6.0) return NO;

    // 省电档位 1：只处理不超过屏幕一半面积的表面。
    // 全屏级别的 backdrop（通知中心整页、锁屏壁纸层）本身已经很贵，再加网格会把 GPU 拉满。
    if (perfMode == 1) {
        UIView *reference = view.window ?: view;
        CGRect referenceBounds = reference.bounds;
        double referenceArea = (double)CGRectGetWidth(referenceBounds) * (double)CGRectGetHeight(referenceBounds);
        double area = (double)width * (double)height;
        if (referenceArea > 0.0 && area > referenceArea * 0.55) return NO;
    }

    CALayer *backdrop = AxsFindBackdropLayer(view.layer, 0);
    if (!backdrop) {
        gAxsMeshMissCount += 1;
        if (!gAxsMeshLogged && gAxsMeshMissCount >= 20) {
            gAxsMeshLogged = YES;
            AxsLog(@"折射：%ld 个表面没找到 CABackdropLayer（背景层不在预期层级），跳过",
                   (long)gAxsMeshMissCount);
        }
        return NO;
    }

    id mesh = AxsMeshForGeometry(width, height, radius, strength);
    if (!mesh) return NO;

    // 记住原始 grid，关闭功能时原样还回去。
    if (!objc_getAssociatedObject(view, &kAxsMeshOriginalKey)) {
        id original = nil;
        @try {
            original = [backdrop valueForKey:@"meshTransform"];
        } @catch (NSException *exception) {
            (void)exception;
        }
        if (original) {
            objc_setAssociatedObject(view, &kAxsMeshOriginalKey, original,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }

    if (!AxsSetMeshTransform(backdrop, mesh)) return NO;

    objc_setAssociatedObject(view, &kAxsMeshAppliedKey, @(strength), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    gAxsMeshAppliedCount += 1;
    if (gAxsMeshAppliedCount == 1) {
        AxsLog(@"折射：首次生效 %@（%.0fx%.0f，圆角 %.0f，强度 %.2f，层级 %@）",
               NSStringFromClass([view class]), width, height, radius, strength,
               NSStringFromClass([backdrop class]));
    }
    return YES;
}

+ (void)axs_liquidglass_clearRefractionFromView:(UIView *)view {
    if (!view) return;
    if (!objc_getAssociatedObject(view, &kAxsMeshAppliedKey)) return;

    CALayer *backdrop = AxsFindBackdropLayer(view.layer, 0);
    id original = objc_getAssociatedObject(view, &kAxsMeshOriginalKey);
    if (backdrop) {
        AxsSetMeshTransform(backdrop, original);
    }
    objc_setAssociatedObject(view, &kAxsMeshAppliedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, &kAxsMeshOriginalKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@end

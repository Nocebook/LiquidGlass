#pragma once

#import <Preferences/PSTableCell.h>
#import <Preferences/PSSpecifier.h>
#include <math.h>

@protocol AxsLiquidGlassSliderCellHandler <NSObject>
- (double)axs_liquidglass_sliderValueForSpecifier:(PSSpecifier *)specifier;
- (void)axs_liquidglass_setSliderValue:(double)value specifier:(PSSpecifier *)specifier;
@end

@interface AxsLiquidGlassSliderCell : PSTableCell
@property (nonatomic, weak) id<AxsLiquidGlassSliderCellHandler> handler;
- (void)axs_liquidglass_reloadState;
@end

//
//  OULessonCell.m
//  ITMOSchedule
//
//  Created by Ruslan Kavetsky on 10/14/13.
//  Copyright (c) 2013 Ruslan Kavetsky. All rights reserved.
//

#import "OULessonCell.h"
#import "UILabel+Adjust.h"
#import "UIFont+PreferedFontSize.h"

@implementation OULessonCell

+ (CGFloat)cellHeight {
    return 100.0;
}

- (void)setLesson:(OULesson *)lesson {
    _lesson = lesson;

    [self updateFonts];
    [self updateTimeLabel];
    [self updateTopLabel];
    [self updateCenterLabel];
    [self updateBottomLabel];
    [self adjustLabelsSize];
}

- (void)awakeFromNib {
    [super awakeFromNib];

    self.topLabel.textColor = self.bottomLabel.textColor = [UIColor colorWithWhite:0.400 alpha:1.000];

    self.selectedBackgroundView.backgroundColor = ICON_COLOR;
}

- (void)updateFonts {
    NSString *topBottomStyle = UIFontTextStyleCaption1;

    self.topLabel.font = [UIFont preferredFontForTextStyle:topBottomStyle];
	self.centerLabel.font = [self.class centerLabelFont];
    self.bottomLabel.font = [UIFont preferredFontForTextStyle:topBottomStyle];
    self.timeLabel.font = [UIFont preferredTimeFont];
}

+ (UIFont*)centerLabelFont {
	return [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
}

- (void)adjustLabelsSize {
    [self.topLabel adjustSizeWithMaximumWidth:self.topLabelView.$width];
    [self.centerLabel adjustSizeForAttributedStringWithMaximumWidth:self.centerLabelView.$width];
    [self.bottomLabel adjustSizeWithMaximumWidth:self.bottomLabelView.$width];
}

- (void)updateTimeLabel {
    if (_lesson.timeInterval) {
        _timeLabel.text = _lesson.timeInterval;
    } else {
        NSString *startTime = [NSString stringWithFormat:@"%2d:%.2d", _lesson.startTime / 100, _lesson.startTime % 100];
        NSString *finishTime = [NSString stringWithFormat:@"%2d:%.2d", _lesson.finishTime / 100, _lesson.finishTime % 100];
        _timeLabel.text = [NSString stringWithFormat:@"%@\n%@", startTime, finishTime];
    }
}

#define LESSON_TYPE_TEXT_COLOR [UIColor colorWithWhite:0.500 alpha:1.000]

- (void)updateCenterLabel {

    UIColor *typeTextColor = LESSON_TYPE_TEXT_COLOR;

    if (_lesson.additionalInfo) {
        _centerLabel.attributedText = [self.class attributesToNameWithColor:typeTextColor lesson:self.lesson];
    } else if (_lesson.lessonType != OULessonTypeUnknown) {
        _centerLabel.attributedText = [self.class attributesToNameWithColor:typeTextColor lesson:self.lesson];
    } else {
        _centerLabel.text = _lesson.lessonName;
    }
}

- (void)updateTopLabel {}

- (void)updateBottomLabel {}

- (NSString *)groupsString {
    NSMutableString *groupsString = [@"" mutableCopy];
    for (OUGroup *group in self.lesson.groups) {
        [groupsString appendFormat:@"%@, ", group.groupName];
    }
    [groupsString replaceCharactersInRange:NSMakeRange(groupsString.length - 2, 2) withString:@""];
    return [groupsString copy];
}

#define SPACE 5.0
#define MIN_CELL_HEIGHT 44.0

- (void)layoutSubviews {
    [super layoutSubviews];

    [self adjustLabelsSize];    

    self.topLabel.$y = SPACE;
    self.centerLabel.$y = self.topLabel.$bottom;
    self.bottomLabel.$y = self.centerLabel.$bottom;
    self.timeLabel.$height = self.topLabel.$height + self.centerLabel.$height + self.bottomLabel.$height + SPACE * 2;

    if ((self.timeLabel.$height < MIN_CELL_HEIGHT) && (self.topLabel.$height == 0) && (self.bottomLabel.$height == 0)) {
        self.centerLabel.$y = 0;
        self.centerLabel.$height = MIN_CELL_HEIGHT;
        self.timeLabel.$height = MIN_CELL_HEIGHT;
    }
}

#pragma mark - Height

+ (CGFloat)cellHeightForLesson:(OULesson *)lesson width:(CGFloat)width {
	NSString *topBottomStyle = UIFontTextStyleCaption1;
	CGFloat lessonH = [[self attributesToNameWithColor:[UIColor clearColor] lesson:lesson] boundingRectWithSize:(CGSize){width - 60.0, MAXFLOAT} options:NSStringDrawingUsesLineFragmentOrigin context:NULL].size.height;
	CGFloat topBottomH = [@" " sizeWithAttributes:@{NSFontAttributeName : [UIFont preferredFontForTextStyle:topBottomStyle]}].height;
    return ceil(lessonH + (2 * topBottomH) + (3 * SPACE));
}

- (CGFloat)height {
    return MAX(_topLabel.$height + _centerLabel.$height + _bottomLabel.$height + SPACE * 2, MIN_CELL_HEIGHT);
}

#pragma mark - Highlited & attributed

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [super setHighlighted:highlighted animated:animated];

    UIColor *textColor;
    if (highlighted) {
        textColor = [UIColor whiteColor];
    } else {
        textColor = LESSON_TYPE_TEXT_COLOR;
    }
    _centerLabel.attributedText = [self.class attributesToNameWithColor:textColor lesson:self.lesson];
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    [super setSelected:selected animated:animated];
    UIColor *textColor;
    if (selected) {
        textColor = [UIColor whiteColor];
    } else {
        textColor = LESSON_TYPE_TEXT_COLOR;
    }

    // Чтобы смена цветов была плавная и соответствовала анимации смены цвета фона
    if (animated) {
        double delayInSeconds = 0.25;
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
        dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
			_centerLabel.attributedText = [self.class attributesToNameWithColor:textColor lesson:self.lesson];
        });
    } else {
        _centerLabel.attributedText = [self.class attributesToNameWithColor:textColor lesson:self.lesson];
    }
}

+ (NSAttributedString*)attributesToNameWithColor:(UIColor *)color lesson:(OULesson*) lesson{
	NSString *shortLessontType = [OULesson shortStringForLessonType:lesson.lessonType];
	UIColor *typeTextColor = color;
	NSString *typeTextStyle = UIFontTextStyleBody;
	NSDictionary *typeAttributes = @{NSForegroundColorAttributeName : typeTextColor,
									 NSFontAttributeName : [UIFont preferredFontForTextStyle:typeTextStyle],
									 };
	
	if (lesson.additionalInfo) {
		NSString *text = [NSString stringWithFormat:@"%@ (%@)\n%@", lesson.lessonName, shortLessontType, lesson.additionalInfo];
		
		NSMutableAttributedString *attrString = [[NSMutableAttributedString alloc] initWithString:text];
		[attrString addAttributes:@{NSFontAttributeName : [self centerLabelFont]}
							range:NSMakeRange(0, attrString.length)];
		[attrString addAttributes:typeAttributes
							range:[text rangeOfString:[NSString stringWithFormat:@"(%@)", shortLessontType]]];
		
		return attrString;
		
	} else if (lesson.lessonType != OULessonTypeUnknown) {
		NSString *text = [NSString stringWithFormat:@"%@ (%@)", lesson.lessonName, shortLessontType];
		
		NSMutableAttributedString *attrString = [[NSMutableAttributedString alloc] initWithString:text];
		[attrString addAttributes:@{NSFontAttributeName : [self centerLabelFont]}
							range:NSMakeRange(0, attrString.length)];
		[attrString addAttributes:typeAttributes
							range:[text rangeOfString:[NSString stringWithFormat:@"(%@)", shortLessontType]]];
		
		return attrString;
	}
	return nil;
}

@end

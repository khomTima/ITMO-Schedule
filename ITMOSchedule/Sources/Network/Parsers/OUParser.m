//
//  OUParser.m
//  ITMOSchedule
//
//  Created by Misha on 10/9/13.
//  Copyright (c) 2013 Ruslan Kavetsky. All rights reserved.
//

#import "OUParser.h"
#import "RXMLElement.h"
#import "OUScheduleCoordinator.h"
#import "NSArray+Helpers.h"
#import "NSString+Helpers.h"

@implementation OUParser

+ (NSDictionary *)parseMainInfo:(NSData *)XMLData {

    NSMutableArray *groups = [NSMutableArray array];
    NSMutableArray *teachers = [NSMutableArray array];
    NSMutableArray *auditories = [NSMutableArray array];

    RXMLElement *rootElement = [RXMLElement elementFromXMLData:XMLData];

    [rootElement iterate:@"GROUPS.GROUP_ID" usingBlock: ^(RXMLElement *groupElement) {
        OUGroup *group = [OUGroup new];
        group.groupName = groupElement.text;
        [groups addObject:group];
    }];

    [rootElement iterate:@"TEACHERS.TEACHER" usingBlock:^(RXMLElement *teacherElement) {
        OUTeacher *teacher = [OUTeacher new];
        teacher.teacherId = [teacherElement child:@"TEACHER_ID"].text;
        teacher.teacherName = [[teacherElement child:@"TEACHER_FIO"].text stringByDeletingDataInBrackets];
        teacher.teaherPosition = [[teacherElement child:@"TEACHER_FIO"].text stringFromBrackets];
        [teachers addObject:teacher];
    }];

    [rootElement iterate:@"AUDITORIES.AUDITORY_ID" usingBlock:^(RXMLElement *auditoryElement) {
        OUAuditory *auditory = [OUAuditory new];
        auditory.auditoryName = auditoryElement.text;
        [auditories addObject:auditory];
    }];

    return @{GROUPS_INFO_KEY: groups, TEACHERS_INFO_KEY: teachers, AUDITORIES_INFO_KEY: auditories};
}

+ (NSArray *)parseLessons:(NSData *)XMLData forGroup:(OUGroup *)group {
    NSMutableArray *lessons = [NSMutableArray  array];

    RXMLElement *rootElement = [RXMLElement elementFromXMLData:XMLData];

    __block NSString *weekDay;

    [rootElement iterate:@"WEEKDAY" usingBlock:^(RXMLElement *weekDayElement) {
        weekDay = [weekDayElement attribute:@"value"];
        [weekDayElement iterate:@"DESCRIPTION.SCHEDULE.SCHEDULE_PARAM" usingBlock:^(RXMLElement *lessonElement) {
            OULesson *lesson = [OULesson new];

            if (group) lesson.groups = @[group];
            lesson.weekDay = [OULesson weekDayFromString:weekDay];
            [self parseLessonInfoForElement:lessonElement intoLesson:lesson];
            lesson.teacher = [self parseTeacherForElement:lessonElement nameTag:@"LECTURER" idTag:@"LECTUTER_ID"];

            [lessons addObject:lesson];
        }];
    }];

    return lessons;
}

+ (NSArray *)parseLessons:(NSData *)XMLData forAuditory:(OUAuditory *)auditory {
    NSMutableArray *lessons = [NSMutableArray  array];

    RXMLElement *rootElement = [RXMLElement elementFromXMLData:XMLData];

    __block NSString *weekDay;

    [rootElement iterate:@"WEEKDAY" usingBlock:^(RXMLElement *weekDayElement) {
        weekDay = [weekDayElement attribute:@"value"];
        [weekDayElement iterate:@"DESCRIPTION_A.SCHEDULE.SCHEDULE_PARAM_A" usingBlock:^(RXMLElement *lessonElement) {
            OULesson *lesson = [OULesson new];

            lesson.groups = [self groupsFromString:[lessonElement child:@"GROUP_NUMBER"].text];
            lesson.weekDay = [OULesson weekDayFromString:weekDay];
            [self parseLessonInfoForElement:lessonElement intoLesson:lesson];
            lesson.teacher = [self parseTeacherForElement:lessonElement nameTag:@"TEACHER_NAME" idTag:@"TEACHER_ID"];

            [lessons addObject:lesson];
        }];
    }];

    return lessons;
}

+ (NSArray *)parseLessons:(NSData *)XMLData forTeacher:(OUTeacher *)teacher {
    NSMutableArray *lessons = [NSMutableArray  array];

    RXMLElement *rootElement = [RXMLElement elementFromXMLData:XMLData];

    __block NSString *weekDay;

    [rootElement iterate:@"WEEKDAY" usingBlock:^(RXMLElement *weekDayElement) {
        weekDay = [weekDayElement attribute:@"value"];
        [weekDayElement iterate:@"DESCRIPTION_P.SCHEDULE.SCHEDULE_PARAM_P" usingBlock:^(RXMLElement *lessonElement) {
            OULesson *lesson = [OULesson new];

            lesson.groups = [self groupsFromString:[lessonElement child:@"GROUP_NUMBER"].text];
            lesson.weekDay = [OULesson weekDayFromString:weekDay];
            [self parseLessonInfoForElement:lessonElement intoLesson:lesson];
            lesson.teacher = teacher;

            [lessons addObject:lesson];
        }];
    }];

    return lessons;
}

+ (int)parseWeekNumber:(NSData *)XMLData {
    RXMLElement *rootElement = [RXMLElement elementFromXMLData:XMLData];

    return rootElement.text.intValue;
}

#pragma mark - Little parsers

+ (OUTeacher *)parseTeacherForElement:(RXMLElement *)element nameTag:(NSString *)nametag idTag:(NSString *)idTag {
    OUTeacher *teacher = [[OUTeacher alloc] init];
    teacher.teacherName = [[element child:nametag] text];
    teacher.teacherId = [[element child:idTag] text];
    return teacher;
}

+ (void)parseLessonInfoForElement:(RXMLElement *)element intoLesson:(OULesson *)lesson {
    NSString *timeInterval = [[element child:@"TIME_INTERVAL"] text];
    OULessonTime startTime;
    OULessonTime finishTime;
    if ([self startTime:&startTime finishTime:&finishTime fromString:timeInterval]) {
        lesson.startTime = startTime;
        lesson.finishTime = finishTime;
    } else {
        lesson.timeInterval = timeInterval;
    }
    lesson.weekType = [OULesson weekTypeFromString:[[element child:@"WEEK"] text]];
    lesson.address = [[[element child:@"PLACE"] text] stringByDeletingNewLineCharacters];
    lesson.lessonName = [[element child:@"SUBJECT"].text stringByDeletingDataInBrackets];
    lesson.lessonType = [OULesson lessonTypeFromString:[[element child:@"SUBJECT"] text]];
}

#pragma mark - Helpers

+ (NSString *)startTime:(OULessonTime *)startTime finishTime:(OULessonTime *)finishTime fromString:(NSString *)string {
    NSArray *components = [string componentsSeparatedByString:@"-"];

    if (components.count == 1 || components.count == 0) {
        return nil;
    }

    NSString *startTimeString = components[0];
    NSString *finishTimeString = components[1];

    NSArray *startTimeComponents = [startTimeString componentsSeparatedByString:@":"];
    OULessonTime s = [startTimeComponents[0] intValue] * 100 + [startTimeComponents[1] intValue];
    *startTime = s;

    NSArray *finishTimeComponents = [finishTimeString componentsSeparatedByString:@":"];
    OULessonTime f = [finishTimeComponents[0] intValue] * 100 + [finishTimeComponents[1] intValue];
    *finishTime = f;

    return string;
}

+ (NSArray *)groupsFromString:(NSString *)string {
    NSArray *groupsStrings = [string componentsSeparatedByString:@","];
    NSMutableArray *groups = [NSMutableArray array];
    for (NSString *s in groupsStrings) {
        OUGroup *group = [OUGroup new];
        group.groupName = s;
        [groups addObject:group];
    }
    return [groups copy];
}

@end

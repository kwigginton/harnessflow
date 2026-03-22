#import <Foundation/Foundation.h>

#if __has_attribute(swift_private)
#define AC_SWIFT_PRIVATE __attribute__((swift_private))
#else
#define AC_SWIFT_PRIVATE
#endif

/// The "ImplementPhase" asset catalog image resource.
static NSString * const ACImageNameImplementPhase AC_SWIFT_PRIVATE = @"ImplementPhase";

/// The "PlanPhase" asset catalog image resource.
static NSString * const ACImageNamePlanPhase AC_SWIFT_PRIVATE = @"PlanPhase";

/// The "ResearchPhase" asset catalog image resource.
static NSString * const ACImageNameResearchPhase AC_SWIFT_PRIVATE = @"ResearchPhase";

/// The "ReviewPhase" asset catalog image resource.
static NSString * const ACImageNameReviewPhase AC_SWIFT_PRIVATE = @"ReviewPhase";

#undef AC_SWIFT_PRIVATE

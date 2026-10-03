#ifndef TikTokHeaders_h
#define TikTokHeaders_h

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// Forward declarations of common TikTok classes (names are stable across recent TikTok versions).
// We never call these directly - they're only used in %hook/%c().

@class AWEURLModel;
@class AWEAwemeModel;
@class AWEMusicModel;
@class AWEVideoModel;
@class AWEPlayVideoPlayerController;
@class AWEFeedViewTemplateCell;
@class AWEAwemeDetailTableViewCell;
@class TTKStoryDetailTableViewCell;
@class AWEFeedCellViewController;
@class AWEAwemeDetailCellViewController;
@class TTKStoryDetailContainerViewController;
@class TTKPhotoAlbumFeedCellController;
@class TTKPhotoAlbumDetailCellController;
@class TTKStoryContainerViewController;
@class AWEPlayPhotoAlbumViewController;
@class AWEPhotoAlbumPhoto;
@class TUXActionSheetController;
@class TUXActionSheetAction;
@class AWEUIAlertView;
@class AWEToast;
@class TTKSettingsBaseCellPlugin;
@class AWESettingsNormalSectionViewModel;
@class AWESettingItemModel;
@class AWEAwemeBaseViewController;
@class TTKFeedInteractionLegacyMainContainerElement;

#endif
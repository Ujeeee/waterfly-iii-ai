# Waterfly III

<p align="center">
  <a href="https://play.google.com/store/apps/details?id=com.dreautall.waterflyiii"><img src=".playstore/en_badge_web_generic.png" width="200" /></a>
  <!--<a href="https://f-droid.org/en/packages/com.dreautall.waterflyiii/"><img src=".github/assets/fdroid_get-it-on.ong" width="200" /></a>-->
</p>

**Unofficial** Android App for [Firefly III](https://github.com/firefly-iii/firefly-iii), a free and open source personal finance manager.

The app design is heavily influenced
by [Bluecoins](https://play.google.com/store/apps/details?id=com.rammigsoftware.bluecoins). Please
also read the [FAQ](https://github.com/dreautall/waterfly-iii/blob/master/FAQ.md).

## Features

- General
  - Light & Dark mode, supports dynamic colors
  - Translation ready - [**help to translate via Crowdin**](https://crowdin.com/project/waterfly-iii)!
  - Listen to incoming notifications (e.g., from Google Pay or your banking app) and pre-fill transactions
  - Option to require fingerprint to open the app
- Dashboard
  - Five different charts charts for the current balance & recent history
  - Waterfall chart for net earnings in recent months
  - Budget overview for last 30 days
  - Upcoming bills
- Transactions
  - List transactions by date
  - Ability to filter the list by various fields
  - Add & edit transactions with autocomplete, including attachments and pictures, split transactions & multi currency support
  - **AI-powered receipt parsing** with Google Gemini integration
    - Automatically extract transaction data from receipt photos
    - Multi-language support (English, Indonesian, Spanish, French, German, Japanese, Korean, Chinese)
    - Configurable AI models (Gemini 2.0 Flash, 2.5 Flash, 1.5 Flash, 1.5 Pro, etc.)
    - Auto-fill transaction forms with parsed data
    - Smart categorization and merchant detection
    - **Dual FAB interface**: AI button (🤖) above standard Plus button (+) for easy access
- Balance Sheet
  - List individual account balances
- Piggy Banks
  - View piggy banks, sorted by category
  - Add/Remove money from piggy banks
- Accounts
  - List all asset/expense/revenue/liability accounts
  - Search for specific accounts
- Categories
  - View monthly transactions split up by category
  - Add, edit & delete categories
- Bills
  - View bills and their overview organized into groups
  - Inspect bill details and see connected transactions

## AI-Powered Receipt Parsing

This enhanced version of Waterfly III includes AI-powered receipt parsing capabilities using Google Gemini. This feature allows you to:

### **Setup**

1. Go to **Settings** → **Gemini AI Settings**
2. Enter your Google AI Studio API key (get one at [ai.google.dev](https://ai.google.dev))
3. Select your preferred AI model
4. Choose your preferred language for parsed results

### **Usage**

**Method 1: Quick AI Receipt Parsing**

1. On the main screen, tap the AI button (🤖) - the top floating action button
2. Take a photo of your receipt or upload an existing image
3. The AI will automatically extract transaction data
4. Review and confirm the parsed information

**Method 2: Traditional Transaction Entry with AI Enhancement**

1. Tap the Plus button (+) - the bottom floating action button
2. When adding a transaction, tap the attachments icon (📎)
3. Take a photo of your receipt or upload an existing image
4. Tap the "Parse with AI" button (✨)
5. Review the extracted data in the preview dialog
6. Tap "Auto-Fill Transaction Form" to populate the transaction

### **Features**

- **Dual FAB Interface**: Clean, icon-only floating action buttons for quick access
  - 🤖 AI Receipt Parser (top button)
  - ➕ Standard Transaction Entry (bottom button)
- **Smart Data Extraction**: Automatically detects amount, date, merchant, category, and payment method
- **Multi-Language Support**: Results in your preferred language (merchant names preserved)
- **Configurable Models**: Choose from various Gemini models based on your needs
- **Title Case Categories**: Clean, properly formatted category names
- **Detailed Notes**: Comprehensive receipt information stored in notes field
- **Privacy-Focused**: Images processed by Google AI but not stored permanently

### **Supported Languages**

- English
- Indonesian (default)
- Spanish
- French
- German
- Japanese
- Korean
- Chinese (Simplified)

### Feature Status

The app does **not** try to replicate every single feature that the Webinterface has. Instead, it tries to be a good _companion_ to access the most used functions on-the-go. More in-depth operations such as creating or modifying rules are not planned for this app.

If you are missing anything, feel free to open a [feature request](https://github.com/dreautall/waterfly-iii/issues/new/choose), or look at what other users [are requesting](https://github.com/dreautall/waterfly-iii/issues?q=is%3Aissue+is%3Aopen+label%3Aenhancement).

## Releases

The stable releases are published to the [Google Play Store](https://play.google.com/store/apps/details?id=com.dreautall.waterflyiii), and are also available for download from the [GitHub releases page](https://github.com/dreautall/waterfly-iii/releases/latest). There is no fixed release schedule.

You can also opt in to the (open) beta channel at Google Play [here](https://play.google.com/apps/testing/com.dreautall.waterflyiii). The beta channel will feature the "pre-releases" from the [GitHub releases page](https://github.com/dreautall/waterfly-iii/releases), and might not be as stable.

## Screenshots

_All made with a Google Pixel 8, showing Waterfly III v1.0.0_

|                           Dashboard                           |                               Transactions                                |                           Transaction Filters                            |
| :-----------------------------------------------------------: | :-----------------------------------------------------------------------: | :----------------------------------------------------------------------: |
| <img src=".github/assets/screen_dashboard.png" width="250" /> | <img src=".github/assets/screen_transactions_overview.png" width="250" /> | <img src=".github/assets/screen_transactions_filters.png" width="250" /> |

|                           Transaction Add                           |                           Transaction Edit                           |                           Transaction Attachments                           |
| :-----------------------------------------------------------------: | :------------------------------------------------------------------: | :-------------------------------------------------------------------------: |
| <img src=".github/assets/screen_transaction_add.png" width="250" /> | <img src=".github/assets/screen_transaction_edit.png" width="250" /> | <img src=".github/assets/screen_transaction_attachments.png" width="250" /> |

|                        Account Screen                        |                        Category Screen                         |                     Piggy Banks with Chart                      |
| :----------------------------------------------------------: | :------------------------------------------------------------: | :-------------------------------------------------------------: |
| <img src=".github/assets/screen_accounts.png" width="250" /> | <img src=".github/assets/screen_categories.png" width="250" /> | <img src=".github/assets/screen_piggy_chart.png" width="250" /> |

## Technology

The app is built using [Flutter](https://flutter.dev/), and tries to keep to the [Material 3](https://m3.material.io/) design guidelines. Additionally, I try to keep the app as "lean" as possible, **without any trackers** or unneeded dependency on external packages.

## Known Issues Fixed

### Android Back Button Issue (v1.2.0+)

**Issue**: App would minimize/close when pressing the Android system back button instead of navigating properly.

**Root Cause**: A combination of factors interfered with Flutter's navigation:

- Android 13+ predictive back gestures (`enableOnBackInvokedCallback="true"`) conflicting with Flutter navigation
- Custom page transitions (`CupertinoPageTransitionsBuilder`) causing navigation conflicts
- Missing root-level back button handling

**Solution**:

- Disabled `enableOnBackInvokedCallback` in AndroidManifest.xml
- Removed custom page transitions that interfered with navigation
- Added root-level `PopScope` to handle edge cases
- Simplified transaction form back button handling

**Result**: Back button now properly navigates between screens. AppBar back buttons continue to work as expected.

## Motivation

Having troubles with [Bluecoins](https://play.google.com/store/apps/details?id=com.rammigsoftware.bluecoins) syncing across devices and not always storing attachments online, I was looking for a self-hosted alternative and discovered [Firefly III](https://www.firefly-iii.org/). After a [quick script to migrate from Bluecoins to Firefly III](https://github.com/dreautall/bluecoins-to-fireflyiii), the only thing left was to download an app to easily track expenses on-the-go… or so I thought.

Unfortunately, I discovered that the existing Android Apps for Firefly III had been either outdated or very buggy and hardly maintained. Always wanting to use Flutter for something, I started to make my own app, modeling it after the Bluecoins app I used so far and its interface that I really liked.

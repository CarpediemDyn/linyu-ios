# Resource provenance

- OriginalLogo and original ic_ VectorDrawables: yehu-imei/linyu, official v3.1.0, MIT (project LICENSE). Their original PNG/XML resources remain untouched.
- Android_*.imageset SVGs generated from original VectorDrawable files preserve source paths, nested transforms, opacity, fill rules and stroke geometry. The conversion script fails on unsupported elements instead of silently dropping them.
- Default Material icons: Google material-design-icons, Apache-2.0; full license retained in Material-Icons-LICENSE.txt. Each source URL and SHA-256 is in ICON_SOURCES.json. These reproduce the Material Icons used by Compose, not SF Symbols substitutes.
- OriginalHome/OriginalSettings/OriginalShower assets are screenshot references. They remain in the repository but are not default wallpaper or interactive UI.
- Android source does not embed a custom font and uses device system typography. Numeric font sizes/weights are explicit in LinYuType and page components; Android/iOS system font metrics must be checked in screenshots and are not asserted to be identical.

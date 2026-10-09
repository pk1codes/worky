
Page1 ( show these page numbers on every page for reference during the dev )
App will ask for google login.( try auto login is possible on abdroid & web )
page2 
Then the app will need a whatsapp number for communication ( no otp required )
ask for all the permissions necessary ( location, camers etc ) in the app - in one place.
Links to terms & condition page.

page3 
the user will see page3 showing image cards from parent folder level1.
Parent folder level1 contains many child profiles catagories ( profile 11,profile 12, profile 13 and so on, together with a parent sub folder level2 )
parent subfolder level2 can have catagories profiles 21, profile 22, profile 23 and so on, together with a parent subfolder level3 )
parent subfolder level3 can have catagories profiles 31, profile 32, profile 33 and so on, together with another parent subfolder level4 )
the above archetecture can go on & on.
these profiles are to be stored catagorywise in the backend firebase database.
a profile under parent1 can have the same name as another profile under parent 2 but is distint from it & will sit & show only where it belongs.
Above archetecture is a simple parent- child relationship setup & the database , storage will also be setup in the same simple manner. 

page4 
Each profile will have below onboarding steps. any user can post multiple profiles. he can see his own profile ( without communication icons )
1. select profile ( duplicate the ui of page 3, so the user will easily know where his profile will appear. profile12 is distint from profile21.
2. provide his living location ( or tap to use phone location. )
3. use camera or upload his pic.( max 5 )
4. use camera or upload his video.( max 5 )
5. use mic or upload his audio ( max 5 )

page5
User profile page showing
his pics, video & audio. allow editing & saving again. allow reuse of media data while posting another new profile. Allow sharing on social media.
his live posting ( provide to pause, delete, edit )
T&C page link.
Contact us link.
Delete Account icon.

page6
the maps page ( use free maps )
when user is on page 3, he could switch to interactive maps view showing the same profiles he was viewing.
the map profiles on tap will dispalay the cards list ( expandable )in the same format as page3.

workflow:
when the app opens
1. the 1st page will show cards with profiles in parent folder level 1.
each profile is a catagory of cards ( showing 1 image of the profile ), scrolling left to right. profile11, profile 12 are catagory names.
2. The catagories scroll vertically.
each card on tap expands the card to show:
all his images ( swipeable ), days ago posted, distance from the phone owner. languages spoken. His video.
3. A whatsapp icon & a phone icon & a Gmail icon, which open users apps for communication. prefill them for convinence.
4. if a parent folder is clicked, the page will show the child profiles on the same page. provide back navigation.
5.the profiles a phone sees will be sorted by proximity to the the phone.


Use a dedicated subagent to verify each of below General instructions & ittirate the design till agreement is arrived at:
design max speed with 5000 DAU.
design for minimum app running costs.Minimum backend costs.
Modern UI for current generation appeal.
Ease of use, minimum steps.
frontend talks to backend like an API, not direct calls.
Maximum security against all types of attacks.



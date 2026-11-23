Team Members, you NEED these two things before we can ball:

REPO_URL
REPO_KEY

They'll probs be handed out once the packet drops.

======================================================
====================== LINUX =========================
======================================================
If you are a linux player, type something like this:

export REPO_URL='<you-need-the-repo-url>'
export REPO_KEY='<and-also-the-repo-key>'
curl -LO waluigi-servebeer.com/dlc/gleba/deploy-comp.sh
chmod +x deploy-comp.sh
sudo ./deploy-comp.sh "$REPO_URL" "$REPO_KEY"

======================================================
======================= MS-DOS =======================
======================================================
If you are a sigma Windows main, here's your command:

set "REPO_URL=<you-need-the-repo-url>"
set "REPO_KEY=<and-also-the-repo-key>"
curl.exe -LO waluigi-servebeer.com/dlc/gleba/deploy-comp.cmd
curl.exe -LO waluigi-servebeer.com/dlc/gleba/bkp.cmd
deploy-comp.cmd "%REPO_URL%" "%REPO_KEY%"

======================================================
=================== SPOILAGE =========================
======================================================
If you're installing spoilage on the backup box:

export TUNNEL_DOMAIN='<someone-has-this-dont-worry>'
export THE_BOXES=<this is a space-separated list of our boxes>
curl -LO waluigi-servebeer.com/dlc/gleba/setup-spoilage.sh
chmod +x setup-spoilage.sh
sudo ./setup-spoilage.sh "$TUNNEL_DOMAIN" $THE_BOXES

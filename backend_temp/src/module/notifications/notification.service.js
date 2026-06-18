import { Notification } from "../../DB/models/notification.model.js";

export async function createUserNotification(
  userId,
  { title, body, type = "offer", referenceId = null }
) {
  if (type !== "offer") {
    console.log(`[NOTIFICATIONS] Skipped non-offer notification (${type})`);
    return null;
  }

  return Notification.create({
    user: userId,
    title,
    body,
    type: "offer",
    referenceId,
  });
}

export async function getUnreadCount(userId) {
  return Notification.countDocuments({ user: userId, type: "offer", isRead: false });
}

/** Offer notifications are created only when new offers are fetched. */
export async function seedNotificationsIfEmpty(userId) {
  return false;
}

/** Force seed for all users (skips users who already have notifications). */
export async function seedAllUsersNotifications() {
  const { User } = await import("../../DB/models/user.model.js");
  const users = await User.find({ isDeleted: { $ne: true } }).select("_id");
  let seeded = 0;

  for (const user of users) {
    if (await seedNotificationsIfEmpty(user._id)) seeded++;
  }

  return { users: users.length, seeded };
}

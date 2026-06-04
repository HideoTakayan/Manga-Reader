const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require("@firebase/rules-unit-testing");
const fs = require("fs");
const firebase = require("firebase/compat/app");
require("firebase/compat/firestore");

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: "manga-reader-703c5",
    firestore: {
      rules: fs.readFileSync("firestore.rules", "utf8"),
    },
  });
});

beforeEach(async () => {
  await testEnv.clearFirestore();
});

after(async () => {
  if (testEnv) {
    await testEnv.cleanup();
  }
});

describe("Firestore Rules - Patch A", () => {
  describe("R1: Forum Interactions for Muted Users", () => {
    it("Muted user CANNOT create a forum post", async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context.firestore().collection("users").doc("muted_uid").set({
          mutedUntil: firebase.firestore.Timestamp.fromMillis(Date.now() + 100000),
          role: "user"
        });
      });

      const db = testEnv.authenticatedContext("muted_uid").firestore();
      const post = db.collection("forumPosts").doc("post1");

      await assertFails(
        post.set({
          type: "discussion",
          authorId: "muted_uid",
          authorName: "Muted User",
          authorAvatar: "",
          body: "Hello",
          commentCount: 0,
          viewCount: 0,
          reportCount: 0,
          likeCount: 0,
          isDeleted: false,
          createdAt: firebase.firestore.FieldValue.serverTimestamp(),
          updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
        })
      );
    });

    it("Muted user CAN create a forum report", async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context.firestore().collection("users").doc("muted_uid").set({
          mutedUntil: firebase.firestore.Timestamp.fromMillis(Date.now() + 100000),
          role: "user"
        });
        await context.firestore().collection("forumPosts").doc("post1").set({
          isDeleted: false,
        });
      });

      const db = testEnv.authenticatedContext("muted_uid").firestore();
      const reportId = "muted_uid_post_post1";
      const report = db.collection("forumReports").doc(reportId);

      await assertSucceeds(
        report.set({
          id: reportId,
          reporterId: "muted_uid",
          targetType: "post",
          targetId: "post1",
          postId: "post1",
          reason: "Spam",
          status: "pending",
          createdAt: firebase.firestore.FieldValue.serverTimestamp(),
        })
      );
    });
  });

  describe("R2: Owner Permissions", () => {
    it("Owner CAN soft delete their own post", async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context.firestore().collection("users").doc("owner_uid").set({
          role: "user"
        });
        await context.firestore().collection("forumPosts").doc("post1").set({
          authorId: "owner_uid",
          body: "Original text",
          isDeleted: false,
          updatedAt: Date.now(),
        });
      });

      const db = testEnv.authenticatedContext("owner_uid").firestore();
      const post = db.collection("forumPosts").doc("post1");

      await assertSucceeds(
        post.update({
          isDeleted: true,
          updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
        })
      );
    });

    it("Owner CAN edit post body if not deleted", async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context.firestore().collection("users").doc("owner_uid").set({
          role: "user"
        });
        await context.firestore().collection("forumPosts").doc("post1").set({
          authorId: "owner_uid",
          body: "Original text",
          isDeleted: false,
          updatedAt: Date.now(),
        });
      });

      const db = testEnv.authenticatedContext("owner_uid").firestore();
      const post = db.collection("forumPosts").doc("post1");

      await assertSucceeds(
        post.update({
          body: "Updated text",
          updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
        })
      );
    });

    it("Owner CANNOT restore a soft deleted post", async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context.firestore().collection("users").doc("owner_uid").set({
          role: "user"
        });
        await context.firestore().collection("forumPosts").doc("post1").set({
          authorId: "owner_uid",
          body: "Original text",
          isDeleted: true,
          updatedAt: Date.now(),
        });
      });

      const db = testEnv.authenticatedContext("owner_uid").firestore();
      const post = db.collection("forumPosts").doc("post1");

      await assertFails(
        post.update({
          isDeleted: false,
          updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
        })
      );
    });
  });

  describe("R3: Validation", () => {
    it("Fails if body is empty and no gifUrl for comments", async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context.firestore().collection("users").doc("user_uid").set({
          role: "user"
        });
        await context.firestore().collection("forumPosts").doc("post1").set({
          isDeleted: false,
        });
      });

      const db = testEnv.authenticatedContext("user_uid").firestore();
      const post = db.collection("forumPosts").doc("post1");
      const comment = post.collection("comments").doc("comment1");

      await assertFails(
        comment.set({
          authorId: "user_uid",
          authorName: "User",
          authorAvatar: "",
          body: "", // empty body
          likeCount: 0,
          isDeleted: false,
          createdAt: firebase.firestore.FieldValue.serverTimestamp(),
          updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
        })
      );
    });

    it("Succeeds if body is empty but gifUrl is present", async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context.firestore().collection("users").doc("user_uid").set({
          role: "user"
        });
        await context.firestore().collection("forumPosts").doc("post1").set({
          isDeleted: false,
        });
      });

      const db = testEnv.authenticatedContext("user_uid").firestore();
      const post = db.collection("forumPosts").doc("post1");
      const comment = post.collection("comments").doc("comment1");

      await assertSucceeds(
        comment.set({
          authorId: "user_uid",
          authorName: "User",
          authorAvatar: "",
          body: "", 
          gifUrl: "http://example.com/gif.gif",
          likeCount: 0,
          isDeleted: false,
          createdAt: firebase.firestore.FieldValue.serverTimestamp(),
          updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
        })
      );
    });

    it("Succeeds if body is empty but imageUrl is present in comment", async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context.firestore().collection("users").doc("user_uid").set({
          role: "user"
        });
        await context.firestore().collection("forumPosts").doc("post1").set({
          isDeleted: false,
        });
      });

      const db = testEnv.authenticatedContext("user_uid").firestore();
      const post = db.collection("forumPosts").doc("post1");
      const comment = post.collection("comments").doc("comment_image");

      await assertSucceeds(
        comment.set({
          authorId: "user_uid",
          authorName: "User",
          authorAvatar: "",
          body: "",
          imageUrl: "https://example.com/comment.jpg",
          likeCount: 0,
          isDeleted: false,
          createdAt: firebase.firestore.FieldValue.serverTimestamp(),
          updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
        })
      );
    });
  
    it("Fails if comment is too long (1001 chars)", async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context.firestore().collection("users").doc("user_uid").set({ role: "user" });
        await context.firestore().collection("forumPosts").doc("post1").set({ isDeleted: false });
      });
      const db = testEnv.authenticatedContext("user_uid").firestore();
      const comment = db.collection("forumPosts").doc("post1").collection("comments").doc("comment2");
      await assertFails(
        comment.set({
          authorId: "user_uid", authorName: "User", authorAvatar: "",
          body: "a".repeat(1001),
          likeCount: 0, isDeleted: false,
          createdAt: firebase.firestore.FieldValue.serverTimestamp(),
          updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
        })
      );
    });

    it("Fails if message is too long (1001 chars)", async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context.firestore().collection("users").doc("user_uid").set({ role: "user" });
      });
      const db = testEnv.authenticatedContext("user_uid").firestore();
      const message = db.collection("forumMessages").doc("msg1");
      await assertFails(
        message.set({
          authorId: "user_uid", authorName: "User", authorAvatar: "",
          body: "a".repeat(1001),
          isDeleted: false,
          createdAt: firebase.firestore.FieldValue.serverTimestamp(),
        })
      );
    });

    it("Fails if gifUrl is not a string", async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context.firestore().collection("users").doc("user_uid").set({ role: "user" });
        await context.firestore().collection("forumPosts").doc("post1").set({ isDeleted: false });
      });
      const db = testEnv.authenticatedContext("user_uid").firestore();
      const comment = db.collection("forumPosts").doc("post1").collection("comments").doc("comment3");
      await assertFails(
        comment.set({
          authorId: "user_uid", authorName: "User", authorAvatar: "",
          body: "valid body", gifUrl: 123,
          likeCount: 0, isDeleted: false,
          createdAt: firebase.firestore.FieldValue.serverTimestamp(),
          updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
        })
      );
    });

    it("Fails if imageUrl is not a string in post", async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context.firestore().collection("users").doc("user_uid").set({ role: "user" });
      });
      const db = testEnv.authenticatedContext("user_uid").firestore();
      const post = db.collection("forumPosts").doc("post2");
      await assertFails(
        post.set({
          type: "discussion", authorId: "user_uid", authorName: "User", authorAvatar: "",
          body: "valid body", imageUrl: 123,
          likeCount: 0, commentCount: 0, viewCount: 0, reportCount: 0,
          isDeleted: false,
          createdAt: firebase.firestore.FieldValue.serverTimestamp(),
          updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
        })
      );
    });

    it("Fails to update comment to empty body", async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context.firestore().collection("users").doc("user_uid").set({ role: "user" });
        await context.firestore().collection("forumPosts").doc("post1").set({ isDeleted: false });
        await context.firestore().collection("forumPosts").doc("post1").collection("comments").doc("comment4").set({
          authorId: "user_uid", body: "initial", isDeleted: false
        });
      });
      const db = testEnv.authenticatedContext("user_uid").firestore();
      const comment = db.collection("forumPosts").doc("post1").collection("comments").doc("comment4");
      await assertFails(
        comment.update({
          body: "",
          updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
        })
      );
    });

    it("Muted user CANNOT create a comment", async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context.firestore().collection("users").doc("muted_uid").set({
          role: "user", mutedUntil: firebase.firestore.Timestamp.fromMillis(Date.now() + 100000)
        });
        await context.firestore().collection("forumPosts").doc("post1").set({ isDeleted: false });
      });
      const db = testEnv.authenticatedContext("muted_uid").firestore();
      const comment = db.collection("forumPosts").doc("post1").collection("comments").doc("comment_muted");
      await assertFails(
        comment.set({
          authorId: "muted_uid", authorName: "User", authorAvatar: "",
          body: "hello", likeCount: 0, isDeleted: false,
          createdAt: firebase.firestore.FieldValue.serverTimestamp(),
          updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
        })
      );
    });

    it("Fails if likeCount is updated to negative", async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context.firestore().collection("users").doc("user_uid").set({ role: "user" });
        await context.firestore().collection("forumPosts").doc("post1").set({ isDeleted: false, likeCount: 0, commentCount: 0, viewCount: 0, reportCount: 0 });
      });
      const db = testEnv.authenticatedContext("user_uid").firestore();
      const post = db.collection("forumPosts").doc("post1");
      await assertFails(
        post.update({
          likeCount: firebase.firestore.FieldValue.increment(-1),
        })
      );
  
  });

  describe("R4: Home banner settings", () => {
    it("Anyone CAN read home banner settings", async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context.firestore().collection("app_settings").doc("home_banner").set({
          mangaIds: ["manga1", "manga2"],
          updatedAt: firebase.firestore.Timestamp.now(),
        });
      });

      const db = testEnv.unauthenticatedContext().firestore();
      await assertSucceeds(db.collection("app_settings").doc("home_banner").get());
    });

    it("Admin CAN update home banner settings", async () => {
      const db = testEnv.authenticatedContext("admin_uid", {
        email: "admin@gmail.com",
      }).firestore();

      await assertSucceeds(
        db.collection("app_settings").doc("home_banner").set({
          mangaIds: ["manga1", "manga2"],
          updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
        })
      );
    });

    it("Admin CAN delete home banner settings", async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context.firestore().collection("app_settings").doc("home_banner").set({
          mangaIds: ["manga1"],
          updatedAt: firebase.firestore.Timestamp.now(),
        });
      });

      const db = testEnv.authenticatedContext("admin_uid", {
        email: "admin@gmail.com",
      }).firestore();

      await assertSucceeds(db.collection("app_settings").doc("home_banner").delete());
    });

    it("Non-admin CANNOT update home banner settings", async () => {
      const db = testEnv.authenticatedContext("user_uid", {
        email: "user@example.com",
      }).firestore();

      await assertFails(
        db.collection("app_settings").doc("home_banner").set({
          mangaIds: ["manga1"],
          updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
        })
      );
    });

    it("Admin CANNOT write unrelated app settings docs", async () => {
      const db = testEnv.authenticatedContext("admin_uid", {
        email: "admin@gmail.com",
      }).firestore();

      await assertFails(
        db.collection("app_settings").doc("other_setting").set({
          mangaIds: ["manga1"],
          updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
        })
      );
    });
  });

  describe("R5: Reader issue reports", () => {
    it("Signed-in user CAN create a valid reader report", async () => {
      const db = testEnv.authenticatedContext("user_uid", {
        email: "user@example.com",
      }).firestore();
      const report = db.collection("reports").doc("report1");

      await assertSucceeds(
        report.set({
          id: "report1",
          mangaId: "manga1",
          mangaTitle: "Manga One",
          chapterId: "chapter1",
          chapterTitle: "Chapter 1",
          userId: "user_uid",
          reason: "Lỗi ảnh",
          description: "Trang 3 không tải được",
          status: "pending",
          readerType: "manga",
          pageIndex: 2,
          totalPages: 12,
          createdAt: firebase.firestore.FieldValue.serverTimestamp(),
          updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
        })
      );
    });

    it("Signed-in user CANNOT spoof another userId in reader report", async () => {
      const db = testEnv.authenticatedContext("user_uid", {
        email: "user@example.com",
      }).firestore();
      const report = db.collection("reports").doc("report1");

      await assertFails(
        report.set({
          id: "report1",
          mangaId: "manga1",
          mangaTitle: "Manga One",
          chapterId: "chapter1",
          chapterTitle: "Chapter 1",
          userId: "other_uid",
          reason: "Lỗi ảnh",
          description: "Trang 3 không tải được",
          status: "pending",
          readerType: "manga",
          pageIndex: 2,
          totalPages: 12,
          createdAt: firebase.firestore.FieldValue.serverTimestamp(),
          updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
        })
      );
    });

    it("Non-admin CANNOT read reader reports", async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context.firestore().collection("reports").doc("report1").set({
          status: "pending",
        });
      });

      const db = testEnv.authenticatedContext("user_uid", {
        email: "user@example.com",
      }).firestore();

      await assertFails(db.collection("reports").doc("report1").get());
    });

    it("Admin CAN read and resolve reader reports", async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context.firestore().collection("reports").doc("report1").set({
          id: "report1",
          mangaId: "manga1",
          mangaTitle: "Manga One",
          chapterId: "chapter1",
          chapterTitle: "Chapter 1",
          userId: "user_uid",
          reason: "Lỗi ảnh",
          description: "Trang 3 không tải được",
          status: "pending",
          readerType: "manga",
          pageIndex: 2,
          totalPages: 12,
          createdAt: firebase.firestore.Timestamp.now(),
          updatedAt: firebase.firestore.Timestamp.now(),
        });
      });

      const db = testEnv.authenticatedContext("admin_uid", {
        email: "admin@gmail.com",
      }).firestore();
      const report = db.collection("reports").doc("report1");

      await assertSucceeds(report.get());
      await assertSucceeds(
        report.update({
          status: "resolved",
          resolvedBy: "admin_uid",
          resolvedAt: firebase.firestore.FieldValue.serverTimestamp(),
          updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
        })
      );
    });

    it("Admin CANNOT resolve reader report without resolver metadata", async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context.firestore().collection("reports").doc("report1").set({
          id: "report1",
          mangaId: "manga1",
          mangaTitle: "Manga One",
          chapterId: "chapter1",
          chapterTitle: "Chapter 1",
          userId: "user_uid",
          reason: "Lỗi ảnh",
          description: "Trang 3 không tải được",
          status: "pending",
          readerType: "manga",
          pageIndex: 2,
          totalPages: 12,
          createdAt: firebase.firestore.Timestamp.now(),
          updatedAt: firebase.firestore.Timestamp.now(),
        });
      });

      const db = testEnv.authenticatedContext("admin_uid", {
        email: "admin@gmail.com",
      }).firestore();
      const report = db.collection("reports").doc("report1");

      await assertFails(
        report.update({
          status: "resolved",
          updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
        })
      );
    });
  });

  describe("R7: Reader stats validation", () => {
    it("Signed-in user CAN create valid manga stats only", async () => {
      const db = testEnv.authenticatedContext("reader_uid", {
        email: "reader@example.com",
      }).firestore();

      await assertSucceeds(
        db.collection("comics").doc("manga_stats_ok").set({
          viewCount: 1,
          likeCount: 0,
        })
      );
    });

    it("Signed-in user CANNOT create negative manga stats", async () => {
      const db = testEnv.authenticatedContext("reader_uid", {
        email: "reader@example.com",
      }).firestore();

      await assertFails(
        db.collection("comics").doc("manga_stats_bad").set({
          likeCount: -1,
        })
      );
    });

    it("Signed-in user CANNOT create empty manga stats doc", async () => {
      const db = testEnv.authenticatedContext("reader_uid", {
        email: "reader@example.com",
      }).firestore();

      await assertFails(db.collection("comics").doc("manga_stats_empty").set({}));
    });

    it("Signed-in user CANNOT create negative chapter stats", async () => {
      const db = testEnv.authenticatedContext("reader_uid", {
        email: "reader@example.com",
      }).firestore();

      await assertFails(
        db
          .collection("comics")
          .doc("manga1")
          .collection("chapters")
          .doc("chapter_stats_bad")
          .set({
            viewCount: -1,
          })
      );
    });

    it("Signed-in user CAN add viewCount to an existing stats doc that did not have viewCount", async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context.firestore().collection("comics").doc("manga_like_only").set({
          likeCount: 1,
        });
      });

      const db = testEnv.authenticatedContext("reader_uid", {
        email: "reader@example.com",
      }).firestore();

      await assertSucceeds(
        db.collection("comics").doc("manga_like_only").update({
          viewCount: 1,
        })
      );
    });

    it("Signed-in user CAN add a valid rating to an existing stats doc", async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context.firestore().collection("comics").doc("manga_rating_ok").set({
          viewCount: 1,
        });
      });

      const db = testEnv.authenticatedContext("reader_uid", {
        email: "reader@example.com",
      }).firestore();

      await assertSucceeds(
        db.collection("comics").doc("manga_rating_ok").update({
          ratingSum: 5,
          ratingCount: 1,
        })
      );
    });

    it("Signed-in user CANNOT inflate rating stats arbitrarily", async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context.firestore().collection("comics").doc("manga_rating_bad").set({
          ratingSum: 5,
          ratingCount: 1,
        });
      });

      const db = testEnv.authenticatedContext("reader_uid", {
        email: "reader@example.com",
      }).firestore();

      await assertFails(
        db.collection("comics").doc("manga_rating_bad").update({
          ratingSum: 500,
          ratingCount: 100,
        })
      );
    });
  });

  describe("R8: Notification privacy and forum post schema", () => {
    it("User CAN read global notification for a followed manga", async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        const db = context.firestore();
        await db
          .collection("users")
          .doc("reader_uid")
          .collection("following")
          .doc("manga1")
          .set({ mangaId: "manga1" });
        await db.collection("notifications").doc("notif1").set({
          mangaId: "manga1",
          title: "Có chapter mới",
          body: "Truyện đã cập nhật",
          timestamp: firebase.firestore.Timestamp.now(),
        });
      });

      const db = testEnv.authenticatedContext("reader_uid", {
        email: "reader@example.com",
      }).firestore();

      await assertSucceeds(db.collection("notifications").doc("notif1").get());
    });

    it("Signed-in user CANNOT read global notification for an unfollowed manga", async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context.firestore().collection("notifications").doc("notif1").set({
          mangaId: "manga_other",
          title: "Có chapter mới",
          body: "Truyện đã cập nhật",
          timestamp: firebase.firestore.Timestamp.now(),
        });
      });

      const db = testEnv.authenticatedContext("reader_uid", {
        email: "reader@example.com",
      }).firestore();

      await assertFails(db.collection("notifications").doc("notif1").get());
    });

    it("User CAN read legacy comicId notification for a followed manga", async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        const db = context.firestore();
        await db
          .collection("users")
          .doc("reader_uid")
          .collection("following")
          .doc("manga1")
          .set({ mangaId: "manga1" });
        await db.collection("notifications").doc("notif_legacy").set({
          comicId: "manga1",
          title: "Có chapter mới",
          body: "Truyện đã cập nhật",
          timestamp: firebase.firestore.Timestamp.now(),
        });
      });

      const db = testEnv.authenticatedContext("reader_uid", {
        email: "reader@example.com",
      }).firestore();

      await assertSucceeds(
        db.collection("notifications").doc("notif_legacy").get()
      );
    });

    it("Signed-in user CAN read app-wide notification without mangaId", async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context.firestore().collection("notifications").doc("notif_global").set({
          type: "system",
          title: "Thông báo chung",
          body: "Nội dung chung",
          timestamp: firebase.firestore.Timestamp.now(),
        });
      });

      const db = testEnv.authenticatedContext("reader_uid", {
        email: "reader@example.com",
      }).firestore();

      await assertSucceeds(
        db.collection("notifications").doc("notif_global").get()
      );
    });

    it("User CAN create forum comment-like notification for the comment author", async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        const db = context.firestore();
        await db.collection("forumPosts").doc("post1").set({
          authorId: "post_owner_uid",
          isDeleted: false,
        });
        await db
          .collection("forumPosts")
          .doc("post1")
          .collection("comments")
          .doc("comment1")
          .set({
            authorId: "comment_owner_uid",
            isDeleted: false,
          });
      });

      const db = testEnv.authenticatedContext("actor_uid", {
        email: "actor@example.com",
      }).firestore();

      await assertSucceeds(
        db
          .collection("users")
          .doc("comment_owner_uid")
          .collection("forum_notifications")
          .doc("comment_like_post1_comment1_actor_uid")
          .set({
            type: "forum_comment_like",
            recipientId: "comment_owner_uid",
            actorId: "actor_uid",
            actorName: "Actor",
            actorAvatar: "",
            postId: "post1",
            commentId: "comment1",
            postPreview: "Nice comment",
            title: "Actor đã thích bình luận của bạn",
            body: "Nice comment",
            route: "/forum/detail/post1",
            createdAt: firebase.firestore.FieldValue.serverTimestamp(),
            isRead: false,
          })
      );
    });

    it("User CANNOT create forum comment-like notification for a non-author", async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        const db = context.firestore();
        await db.collection("forumPosts").doc("post1").set({
          authorId: "post_owner_uid",
          isDeleted: false,
        });
        await db
          .collection("forumPosts")
          .doc("post1")
          .collection("comments")
          .doc("comment1")
          .set({
            authorId: "comment_owner_uid",
            isDeleted: false,
          });
      });

      const db = testEnv.authenticatedContext("actor_uid", {
        email: "actor@example.com",
      }).firestore();

      await assertFails(
        db
          .collection("users")
          .doc("wrong_recipient_uid")
          .collection("forum_notifications")
          .doc("comment_like_post1_comment1_actor_uid")
          .set({
            type: "forum_comment_like",
            recipientId: "wrong_recipient_uid",
            actorId: "actor_uid",
            actorName: "Actor",
            actorAvatar: "",
            postId: "post1",
            commentId: "comment1",
            postPreview: "Nice comment",
            title: "Actor đã thích bình luận của bạn",
            body: "Nice comment",
            route: "/forum/detail/post1",
            createdAt: firebase.firestore.FieldValue.serverTimestamp(),
            isRead: false,
          })
      );
    });

    it("User CANNOT create forum comment-like notification with a non-stable id", async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        const db = context.firestore();
        await db.collection("forumPosts").doc("post1").set({
          authorId: "post_owner_uid",
          isDeleted: false,
        });
        await db
          .collection("forumPosts")
          .doc("post1")
          .collection("comments")
          .doc("comment1")
          .set({
            authorId: "comment_owner_uid",
            isDeleted: false,
          });
      });

      const db = testEnv.authenticatedContext("actor_uid", {
        email: "actor@example.com",
      }).firestore();

      await assertFails(
        db
          .collection("users")
          .doc("comment_owner_uid")
          .collection("forum_notifications")
          .doc("comment_like_post1_comment1_actor_uid_duplicate")
          .set({
            type: "forum_comment_like",
            recipientId: "comment_owner_uid",
            actorId: "actor_uid",
            actorName: "Actor",
            actorAvatar: "",
            postId: "post1",
            commentId: "comment1",
            postPreview: "Nice comment",
            title: "Actor đã thích bình luận của bạn",
            body: "Nice comment",
            route: "/forum/detail/post1",
            createdAt: firebase.firestore.FieldValue.serverTimestamp(),
            isRead: false,
          })
      );
    });

    it("User CANNOT create post reaction with extra fields", async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        const db = context.firestore();
        await db.collection("users").doc("actor_uid").set({
          role: "user",
        });
        await db.collection("forumPosts").doc("post1").set({
          authorId: "post_owner_uid",
          isDeleted: false,
        });
      });

      const db = testEnv.authenticatedContext("actor_uid", {
        email: "actor@example.com",
      }).firestore();

      await assertFails(
        db
          .collection("forumPosts")
          .doc("post1")
          .collection("reactions")
          .doc("actor_uid")
          .set({
            createdAt: firebase.firestore.FieldValue.serverTimestamp(),
            injected: true,
          })
      );
    });

    it("User CAN create post reaction with only createdAt", async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        const db = context.firestore();
        await db.collection("users").doc("actor_uid").set({
          role: "user",
        });
        await db.collection("forumPosts").doc("post1").set({
          authorId: "post_owner_uid",
          isDeleted: false,
        });
      });

      const db = testEnv.authenticatedContext("actor_uid", {
        email: "actor@example.com",
      }).firestore();

      await assertSucceeds(
        db
          .collection("forumPosts")
          .doc("post1")
          .collection("reactions")
          .doc("actor_uid")
          .set({
            createdAt: firebase.firestore.FieldValue.serverTimestamp(),
          })
      );
    });

    it("User CANNOT create comment reaction with extra fields", async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        const db = context.firestore();
        await db.collection("users").doc("actor_uid").set({
          role: "user",
        });
        await db.collection("forumPosts").doc("post1").set({
          authorId: "post_owner_uid",
          isDeleted: false,
        });
        await db
          .collection("forumPosts")
          .doc("post1")
          .collection("comments")
          .doc("comment1")
          .set({
            authorId: "comment_owner_uid",
            isDeleted: false,
          });
      });

      const db = testEnv.authenticatedContext("actor_uid", {
        email: "actor@example.com",
      }).firestore();

      await assertFails(
        db
          .collection("forumPosts")
          .doc("post1")
          .collection("comments")
          .doc("comment1")
          .collection("reactions")
          .doc("actor_uid")
          .set({
            createdAt: firebase.firestore.FieldValue.serverTimestamp(),
            injected: true,
          })
      );
    });

    it("User CAN create comment reaction with only createdAt", async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        const db = context.firestore();
        await db.collection("users").doc("actor_uid").set({
          role: "user",
        });
        await db.collection("forumPosts").doc("post1").set({
          authorId: "post_owner_uid",
          isDeleted: false,
        });
        await db
          .collection("forumPosts")
          .doc("post1")
          .collection("comments")
          .doc("comment1")
          .set({
            authorId: "comment_owner_uid",
            isDeleted: false,
          });
      });

      const db = testEnv.authenticatedContext("actor_uid", {
        email: "actor@example.com",
      }).firestore();

      await assertSucceeds(
        db
          .collection("forumPosts")
          .doc("post1")
          .collection("comments")
          .doc("comment1")
          .collection("reactions")
          .doc("actor_uid")
          .set({
            createdAt: firebase.firestore.FieldValue.serverTimestamp(),
          })
      );
    });

    it("Owner CANNOT update legacy manga fields on forum post", async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context.firestore().collection("forumPosts").doc("post1").set({
          authorId: "owner_uid",
          body: "Original text",
          isDeleted: false,
          updatedAt: firebase.firestore.Timestamp.now(),
        });
      });

      const db = testEnv.authenticatedContext("owner_uid", {
        email: "owner@example.com",
      }).firestore();

      await assertFails(
        db.collection("forumPosts").doc("post1").update({
          mangaTitle: "Injected title",
          updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
        })
      );
    });

    it("Owner CAN still edit forum post body", async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context.firestore().collection("forumPosts").doc("post1").set({
          authorId: "owner_uid",
          body: "Original text",
          isDeleted: false,
          updatedAt: firebase.firestore.Timestamp.now(),
        });
      });

      const db = testEnv.authenticatedContext("owner_uid", {
        email: "owner@example.com",
      }).firestore();

      await assertSucceeds(
        db.collection("forumPosts").doc("post1").update({
          body: "Updated text",
          updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
        })
      );
    });
  });
});
});

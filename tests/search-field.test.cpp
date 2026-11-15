#include <QClipboard>
#include <QGuiApplication>
#include <QKeyEvent>
#include <QMimeData>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QQuickItem>
#include <QQuickWindow>
#include <QTest>
#include <cstdlib>
#include <iostream>
#include <memory>

static void require(bool condition, const char *message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        std::exit(1);
    }
}

// Count payload reads. Never access the desktop clipboard or send large data.
class ClipboardProbe final : public QMimeData {
public:
    explicit ClipboardProbe(int &reads) : reads_(reads) {}
    QStringList formats() const override { return {QStringLiteral("text/plain")}; }
protected:
    QVariant retrieveData(const QString &, QMetaType) const override {
        ++reads_;
        return QStringLiteral("clipboard text");
    }
private:
    int &reads_;
};

int main(int argc, char **argv) {
    QGuiApplication app(argc, argv);
    require(app.platformName() == "offscreen", "use an isolated clipboard");
    require(argc == 2, "supply the QML test path");
    QQmlEngine engine;
    int reads = 0;
    auto changeClipboard = [&] {
        app.clipboard()->setMimeData(new ClipboardProbe(reads));
        app.processEvents();
    };

    // Prove that this Qt build has the reported automatic payload read.
    {
        QQmlComponent native(&engine);
        native.setData("import QtQuick\nTextInput {}", QUrl());
        std::unique_ptr<QObject> input(native.create());
        require(bool(input), "create the native input");
        changeClipboard();
        require(reads > 0, "the native input must reproduce the clipboard read");
    }
    std::cout << "Native input: automatic clipboard read reproduced.\n";
    reads = 0;

    QQmlComponent component(&engine, QUrl::fromLocalFile(QString::fromLocal8Bit(argv[1])));
    std::unique_ptr<QObject> object(component.create());
    if (!object) std::cerr << component.errorString().toStdString();
    require(bool(object), "create the guarded search field");
    auto *field = qobject_cast<QQuickItem *>(object.get());
    require(field && field->property("readOnly").toBool(), "keep native editing disabled");
    require(reads == 0, "construction must not read an existing clipboard payload");

    QQuickWindow window;
    window.resize(400, 100);
    field->setParentItem(window.contentItem());
    field->setWidth(350);
    window.show();
    window.requestActivate();
    field->forceActiveFocus();
    app.processEvents();
    auto key = [&](Qt::Key code, Qt::KeyboardModifiers modifiers = Qt::NoModifier,
                   const QString &text = QString()) {
        QKeyEvent press(QEvent::KeyPress, code, modifiers, text);
        QGuiApplication::sendEvent(&window, &press);
        QKeyEvent release(QEvent::KeyRelease, code, modifiers, text);
        QGuiApplication::sendEvent(&window, &release);
        app.processEvents();
    };
    auto text = [&] { return field->property("text").toString(); };

    changeClipboard();
    field->setVisible(false);
    changeClipboard();
    field->setVisible(true);
    field->forceActiveFocus();
    changeClipboard();
    require(reads == 0, "visible, hidden, and focused fields must not read clipboard data");

    key(Qt::Key_A, Qt::NoModifier, "a");
    key(Qt::Key_B, Qt::NoModifier, "b");
    require(text() == "ab", "typing must edit the search");
    require(field->property("query").toString() == "ab", "typing must update the query");
    key(Qt::Key_Left);
    key(Qt::Key_X, Qt::ShiftModifier, "X");
    require(text() == "aXb", "insert text at the cursor");
    key(Qt::Key_Backspace);
    require(text() == "ab", "Backspace must remove the previous character");
    key(Qt::Key_Delete);
    require(text() == "a", "Delete must remove the next character");
    key(Qt::Key_A, Qt::ControlModifier);
    key(Qt::Key_E, Qt::NoModifier, QString::fromUtf8("é"));
    require(text() == QString::fromUtf8("é"), "replace a selection with Unicode text");

    for (auto modifiers : {Qt::ControlModifier, Qt::ShiftModifier}) {
        key(modifiers == Qt::ControlModifier ? Qt::Key_V : Qt::Key_Insert, modifiers);
    }
    QTest::mouseClick(&window, Qt::MiddleButton, Qt::NoModifier, QPoint(20, 15));
    require(reads == 0, "paste shortcuts and middle click must not read clipboard data");
    require(text() == QString::fromUtf8("é"), "paste must not change the query");

    key(Qt::Key_End);
    key(Qt::Key_unknown, Qt::NoModifier, QString::fromUtf8("😀"));
    key(Qt::Key_Backspace);
    require(text() == QString::fromUtf8("é"), "Backspace must remove a full surrogate pair");
    key(Qt::Key_unknown, Qt::NoModifier, QString::fromUtf8("😀"));
    key(Qt::Key_Left);
    key(Qt::Key_Delete);
    require(text() == QString::fromUtf8("é"), "Delete must remove a full surrogate pair");
    key(Qt::Key_A, Qt::ControlModifier);
    key(Qt::Key_unknown, Qt::NoModifier, "one two");
    key(Qt::Key_Backspace, Qt::ControlModifier);
    require(text() == "one ", "Control-Backspace must remove the previous word");
    key(Qt::Key_Home);
    key(Qt::Key_Delete, Qt::ControlModifier);
    require(text().isEmpty(), "Control-Delete must remove the next word");
    key(Qt::Key_unknown, Qt::NoModifier, QString(255, 'x'));
    key(Qt::Key_unknown, Qt::NoModifier, QString::fromUtf8("😀"));
    require(text() == QString(255, 'x'), "the length limit must not split a surrogate pair");
    key(Qt::Key_A, Qt::ControlModifier);
    key(Qt::Key_unknown, Qt::NoModifier, QString(300, 'x'));
    require(text().size() == 256, "bound the search length");
    key(Qt::Key_Escape);
    require(text().isEmpty() && field->property("escapes").toInt() == 1,
            "preserve the panel Escape handler");
    key(Qt::Key_A, Qt::NoModifier, "a");
    require(text() == "a" && field->property("query").toString() == "a",
            "typing after Escape must update the query");
    require(reads == 0 && field->property("readOnly").toBool(),
            "editing must never enable native clipboard reads");
    app.clipboard()->clear();
    std::cout << "Search field: keyboard checks passed; clipboard payload reads: " << reads << ".\n";
}

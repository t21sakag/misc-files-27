import XCTest

final class AdaptiveReviewFlowTests: TypographyTestSupport {
    func testAuthoredTextAndReplayControlsBalanceAfterReveal() throws {
        let app = application()
        defer { XCUIDevice.shared.orientation = .portrait }
        let front = """
        <div style="font-size:160px!important"><font id="balance-question" size="7">calculation</font></div>
        <div style="font-size:180px!important"><a id="balance-replay" href="ankiplay://q/0" style="font-size:180px!important;text-decoration:underline">▶︎</a></div>
        <p id="balance-example" style="font-size:16px!important">(check the calculation again)</p>
        <script>
        (()=>{
          const qa=document.getElementById('qa');
          function report(){
            let out=document.getElementById('balance-result');
            if(!out){out=document.createElement('div');out.id='balance-result';out.style='position:fixed;bottom:0;left:0;font-size:12px;background:white;color:black';document.body.append(out);}
            const question=document.getElementById('balance-question'),answer=document.getElementById('balance-answer'),example=document.getElementById('balance-example'),play=document.getElementById('balance-replay');
            const font=getComputedStyle(question).fontSize,icon=play.getBoundingClientRect().height;
            const ok=qa.dataset.studyLayout==='fit' && parseFloat(font)>=30 && parseFloat(font)<=100 && icon>=44 && icon<=48 && font===getComputedStyle(example).fontSize && (!answer || font===getComputedStyle(answer).fontSize);
            out.textContent=ok?'Balanced text verified '+(answer?'answer':'question'):'Balanced text failed '+JSON.stringify({font,icon,state:qa.dataset.studyLayout,answer:answer?getComputedStyle(answer).fontSize:null});
          }
          qa.addEventListener('study-layout',report);
        })();
        </script>
        """
        let back = "<div style=\"font-size:12px!important\"><font id=\"balance-answer\" size=\"2\">計算</font></div><p style=\"font-size:16px!important\">（計算をもう一度確認する）</p>"
        try addNote(front: front, back: back, in: app)
        XCUIDevice.shared.orientation = .landscapeLeft
        requireTestCondition("Balanced review starts in landscape", in: app) { app.frame.width > app.frame.height }
        tapTestControl(app.buttons.matching(identifier: "deck-1"), in: app)
        let web = try XCTUnwrap(waitForTestCardWebView(in: app))
        _ = try XCTUnwrap(waitForTestControl(web.staticTexts.matching(NSPredicate(format: "label == %@", "calculation")), in: app, timeout: 60, purpose: .observation))
        requireTestCondition("Authored font sizes and oversized replay normalize on the question", in: app) {
            web.staticTexts.matching(NSPredicate(format: "label == %@", "Balanced text verified question")).count == 1
        }
        capture("Balanced authored word example and replay", in: app)
        tapTestControl(app.buttons.matching(identifier: "reveal"), in: app)
        requireTestCondition("Question and actual answer retain equal sizes with a bounded replay control", in: app) {
            web.staticTexts.matching(NSPredicate(format: "label == %@", "Balanced text verified answer")).count == 1
        }
        _ = waitForTestControl(app.buttons.matching(identifier: "answer-2"), in: app)
        capture("Balanced authored word meaning examples and rating controls", in: app)
    }


    func testAdaptiveReviewRefitsMediaAndKeepsInputAcrossRotation() throws {
        let app = application()
        defer { XCUIDevice.shared.orientation = .portrait }
        let html = """
        <div id="adaptive-question" style="font-size:18px">English and 日本語の問題</div>
        <hr><div id="adaptive-answer" style="font-size:40px">画像と音声を含む答え</div>
        <audio controls></audio><video controls style="width:180px;height:90px"></video>
        <input id="adaptive-input" value="Keep this answer"><div id="adaptive-media"></div>
        <script>
        (()=>{
          const qa=document.getElementById('qa');let added=false;
          const report=()=>{
            let out=document.getElementById('adaptive-result');
            if(!out){out=document.createElement('div');out.id='adaptive-result';out.style='position:fixed;bottom:0;left:0;font-size:12px;background:white;color:black';document.body.append(out);}
            const question=document.getElementById('adaptive-question'),answer=document.getElementById('adaptive-answer'),image=document.getElementById('adaptive-picture');
            if(!added){added=true;const picture=document.createElement('img');picture.id='adaptive-picture';picture.alt='Adaptive image';picture.src='data:image/svg+xml,%3Csvg xmlns="http://www.w3.org/2000/svg" width="900" height="600"%3E%3Crect width="900" height="600" fill="orange"/%3E%3C/svg%3E';document.getElementById('adaptive-media').append(picture);return;}
            const font=getComputedStyle(question).fontSize;
            const ok=image?.naturalWidth>0 && qa.dataset.studyLayout==='fit' && font===getComputedStyle(answer).fontSize && document.getElementById('adaptive-input').value==='Keep this answer' && image.getBoundingClientRect().height<=Number(qa.dataset.studyAvailableHeight)*.55+1;
            out.textContent=ok?'Adaptive media verified '+(innerWidth>innerHeight?'landscape':'portrait'):'Adaptive media pending '+JSON.stringify({font,state:qa.dataset.studyLayout,loaded:image?.naturalWidth});
          };
          qa.addEventListener('study-layout',report);
        })();
        </script>
        """
        try addNote(front: html, back: "English answer 日本語の答え", in: app)
        tapTestControl(app.buttons.matching(identifier: "deck-1"), in: app)
        let web = try XCTUnwrap(waitForTestCardWebView(in: app))
        // This fixture starts the native audio/video processes on first use.
        // Recorded WebKit layer-tree startup took 38.93s before any content
        // existed. Establish real document readiness before timing layout.
        _ = try XCTUnwrap(waitForTestControl(web.staticTexts.matching(NSPredicate(format: "label == %@", "English and 日本語の問題")),
                                             in: app, timeout: 60, purpose: .observation))
        requireTestCondition("Real media completes adaptive portrait layout", in: app) {
            web.staticTexts.matching(NSPredicate(format: "label == %@", "Adaptive media verified portrait")).count == 1
        }
        capture("Adaptive media and equal text portrait", in: app)
        XCUIDevice.shared.orientation = .landscapeLeft
        requireTestCondition("Real media and input refit in landscape", in: app) {
            app.frame.width > app.frame.height && web.staticTexts.matching(NSPredicate(format: "label == %@", "Adaptive media verified landscape")).count == 1
        }
        capture("Adaptive media and equal text landscape", in: app)
        tapTestControl(app.buttons.matching(identifier: "reveal"), in: app)
        _ = waitForTestControl(app.buttons.matching(identifier: "answer-2"), in: app)
    }

    func testAdaptiveLongContentKeepsReadableMinimumAndNativeButtons() throws {
        let app = application()
        let html = """
        <div id="long-question"></div><hr><div id="long-answer">長文の答え</div>
        <script>
        (()=>{
          document.getElementById('long-question').textContent='English sentences and 日本語の長い説明。 '.repeat(150);
          const qa=document.getElementById('qa');
          qa.addEventListener('study-layout',()=>{
            let out=document.getElementById('long-result');
            if(!out){out=document.createElement('div');out.id='long-result';out.style='position:fixed;bottom:0;left:0;font-size:12px;background:white;color:black';document.body.append(out);}
            const font=getComputedStyle(document.getElementById('long-question')).fontSize;
            const ok=qa.dataset.studyLayout==='scroll' && Number(qa.dataset.studyFont)>=26 && qa.scrollHeight>Number(qa.dataset.studyAvailableHeight) && font===getComputedStyle(document.getElementById('long-answer')).fontSize;
            out.textContent=ok?'Long content verified':'Long content failed '+JSON.stringify({font,state:qa.dataset.studyLayout});
          });
        })();
        </script>
        """
        try addNote(front: html, back: "Long answer", in: app)
        tapTestControl(app.buttons.matching(identifier: "deck-1"), in: app)
        let web = try XCTUnwrap(waitForTestCardWebView(in: app))
        requireTestCondition("Long real content retains its readable minimum and scrolling", in: app) {
            web.staticTexts.matching(NSPredicate(format: "label == %@", "Long content verified")).count == 1
        }
        capture("Long content with native reveal button", in: app)
        tapTestControl(app.buttons.matching(identifier: "reveal"), in: app)
        _ = waitForTestControl(app.buttons.matching(identifier: "answer-2"), in: app)
        capture("Long content with native rating buttons", in: app)
    }
}

(function () {
  'use strict';

  const sendToReactNative = (type, data) => {
    window?.ReactNativeWebView?.postMessage?.(JSON.stringify({ type, data }));
  };

  // Intercept XMLHttpRequest to inject fingerprint/deviceName when server saves finger
  const origOpen = XMLHttpRequest.prototype.open;
  const origSend = XMLHttpRequest.prototype.send;

  XMLHttpRequest.prototype.open = function (method, url, ...rest) {
    this._url = url;
    this._method = method;
    return origOpen.apply(this, [method, url, ...rest]);
  };

  XMLHttpRequest.prototype.send = function (body) {
    if (
      this._url === '/b/doubleAuth/personal/saveFinger' &&
      typeof body === 'string'
    ) {
      const params = new URLSearchParams(body);
      params.set('fingerprint', '${fingerPrint}');
      params.set('deviceName', '${deviceName}');
      params.set('radioVal', '是');
      body = params.toString();
    }

    this._body = body;
    this.addEventListener('load', () => {
      // sendToReactNative('XHR_RESPONSE', { method: this._method, url: this._url, status: this.status, requestBody: this._body, response: this.responseText });
    });

    return origSend.apply(this, [body]);
  };

  const setupLoginPage = () => {
    const usernameInput = document.querySelector('input#i_user');
    const passwordInput = document.querySelector('input#i_pass');

    if (!usernameInput || !passwordInput) {
      return false;
    }

    usernameInput.value = '${username}';
    usernameInput.readOnly = true;

    passwordInput.value = '${password}';
    passwordInput.readOnly = true;

    return true;
  };

  const overrideJQuerySubmit = () => {
    if (window.jQuery && !window.jQuery.fn.submit.isOverridden) {
      const originalSubmit = window.jQuery.fn.submit;

      window.jQuery.fn.submit = function () {
        const formElement = this[0];

        const fingerPrintField = formElement.querySelector(
          '[name="fingerPrint"]',
        );
        if (fingerPrintField) {
          fingerPrintField.value = '${fingerPrint}';
        }

        const singleLoginField = formElement.querySelector(
          '[name="singleLogin"]',
        );
        if (singleLoginField && !singleLoginField.checked) {
          singleLoginField.click();
        }

        const formData = new FormData(formElement);
        const requestBody = Object.fromEntries(formData.entries());

        sendToReactNative('JQUERY_SUBMIT', {
          formId: formElement.id,
          requestBody: requestBody,
        });

        return originalSubmit.apply(this, arguments);
      };

      window.jQuery.fn.submit.isOverridden = true;
    }
  };

  const jqueryChecker = setInterval(() => {
    if (window.jQuery) {
      clearInterval(jqueryChecker);
      overrideJQuerySubmit();
    }
  }, 100);

  const runAllTasks = () => {
    setupLoginPage();
  };

  const observer = new MutationObserver(() => {
    observer.disconnect();
    runAllTasks();
    observer.observe(document.documentElement, {
      childList: true,
      subtree: true,
    });
  });
  observer.observe(document.documentElement, {
    childList: true,
    subtree: true,
  });

  runAllTasks();

  return true;
})();

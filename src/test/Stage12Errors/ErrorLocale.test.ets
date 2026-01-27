import { describe, beforeEach, it, expect } from '@ohos/hypium';
import {
  setErrorLocale, getErrorLocale,
  formatErrorMessage, ErrorLocaleMessages, ErrorTemplateContext
} from '../../main/ets/errors/ErrorLocale';

export default function errorLocaleTest() {
  describe('errorLocaleTest', () => {
    beforeEach(() => {
      setErrorLocale('zh');
    });

    it('setErrorLocale should change locale', 0, () => {
      setErrorLocale('en');
      expect(getErrorLocale()).assertEqual('en');
      setErrorLocale('zh');
      expect(getErrorLocale()).assertEqual('zh');
    });

    it('formatErrorMessage should return fallback when not found', 0, () => {
      const result = formatErrorMessage('UNKNOWN', 'fallback');
      expect(result).assertEqual('fallback');
    });

    it('formatErrorMessage should replace placeholders', 0, () => {
      const context = new ErrorTemplateContext();
      context.entityName = 'User';
      const result = formatErrorMessage('ORM001', '{entityName} test', context);
      expect(result.includes('User')).assertEqual(true);
    });

    it('zh locale should have ORM001 message', 0, () => {
      setErrorLocale('zh');
      const context = new ErrorTemplateContext();
      context.entityName = 'Test';
      const result = formatErrorMessage('ORM001', 'fallback', context);
      expect(result.includes('Test')).assertEqual(true);
    });

    it('en locale should have ORM001 message', 0, () => {
      setErrorLocale('en');
      const context = new ErrorTemplateContext();
      context.entityName = 'Test';
      const result = formatErrorMessage('ORM001', 'fallback', context);
      expect(result.includes('Test')).assertEqual(true);
    });

    it('ErrorLocaleMessages should add and get', 0, () => {
      const messages = new ErrorLocaleMessages();
      messages.add('CODE1', 'Message1');
      expect(messages.getMessage('CODE1')).assertEqual('Message1');
      expect(messages.getMessage('MISSING') === null).assertEqual(true);
    });

    it('ErrorTemplateContext should have defaults', 0, () => {
      const context = new ErrorTemplateContext();
      expect(context.entityName).assertEqual('');
      expect(context.min === null).assertEqual(true);
    });

    it('ErrorTemplateContext.getValue should work', 0, () => {
      const context = new ErrorTemplateContext();
      context.entityName = 'User';
      expect(context.getValue('entityName')).assertEqual('User');
      expect(context.getValue('unknown') === null).assertEqual(true);
    });
  });
}

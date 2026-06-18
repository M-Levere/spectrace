import { loginUser, getWelcomeMessage } from '../src/auth';

describe('User Login', () => {
  describe('Successful login with valid credentials', () => {
    it('returns a session token for valid credentials', async () => {
      const result = await loginUser({ email: 'test@example.com', password: 'SecurePass123' });
      expect(result.token).toBeTruthy();
      expect(result.userId).toBe('user-001');
    });

    it('returns the correct welcome message', async () => {
      const session = await loginUser({ email: 'test@example.com', password: 'SecurePass123' });
      const message = await getWelcomeMessage(session.userId);
      expect(message).toBe('Welcome back, Test User');
    });

    it('sets the correct session expiry', async () => {
      const result = await loginUser({ email: 'test@example.com', password: 'SecurePass123' });
      expect(result.expiresIn).toBe(3600);
    });
  });
});

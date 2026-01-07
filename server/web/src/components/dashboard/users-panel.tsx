'use client';

import { useState, useEffect } from 'react';
import { Users, RefreshCw, Plus, Trash2, Shield, Mail, Calendar } from 'lucide-react';
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { StatCard } from '@/components/ui/stat-card';
import { formatRelativeTime } from '@/lib/utils';

interface User {
  id: string;
  email: string;
  display_name: string;
  role: 'admin' | 'user';
  status: 'active' | 'inactive' | 'suspended';
  created_at: string;
  last_login?: string;
}

interface CreateUserForm {
  email: string;
  password: string;
  display_name: string;
  role: 'admin' | 'user';
}

const API_BASE = process.env.NEXT_PUBLIC_API_URL || 'http://localhost:8766';

export function UsersPanel() {
  const [users, setUsers] = useState<User[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [showCreateForm, setShowCreateForm] = useState(false);
  const [creating, setCreating] = useState(false);
  const [formData, setFormData] = useState<CreateUserForm>({
    email: '',
    password: '',
    display_name: '',
    role: 'user',
  });

  const [authNotConfigured, setAuthNotConfigured] = useState(false);

  const fetchUsers = async () => {
    try {
      setError(null);
      setAuthNotConfigured(false);
      const response = await fetch(`${API_BASE}/api/admin/users`);
      if (!response.ok) {
        if (response.status === 404) {
          // API endpoint doesn't exist yet, show empty state
          setUsers([]);
          return;
        }
        if (response.status === 503) {
          // Auth not configured
          setAuthNotConfigured(true);
          setUsers([]);
          return;
        }
        throw new Error(`Failed to fetch users: ${response.status}`);
      }
      const data = await response.json();
      setUsers(data.users || []);
    } catch (err) {
      console.error('Failed to fetch users:', err);
      setError(err instanceof Error ? err.message : 'Failed to fetch users');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchUsers();
  }, []);

  const handleCreateUser = async (e: React.FormEvent) => {
    e.preventDefault();
    setCreating(true);
    setError(null);

    try {
      const response = await fetch(`${API_BASE}/api/admin/users`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(formData),
      });

      if (!response.ok) {
        const data = await response.json();
        throw new Error(data.message || 'Failed to create user');
      }

      setShowCreateForm(false);
      setFormData({ email: '', password: '', display_name: '', role: 'user' });
      fetchUsers();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to create user');
    } finally {
      setCreating(false);
    }
  };

  const handleDeleteUser = async (userId: string) => {
    if (!confirm('Are you sure you want to delete this user?')) return;

    try {
      const response = await fetch(`${API_BASE}/api/admin/users/${userId}`, {
        method: 'DELETE',
      });

      if (!response.ok) {
        throw new Error('Failed to delete user');
      }

      fetchUsers();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to delete user');
    }
  };

  const stats = {
    total: users.length,
    active: users.filter(u => u.status === 'active').length,
    admins: users.filter(u => u.role === 'admin').length,
  };

  const statusStyles: Record<string, { color: string; variant: 'success' | 'warning' | 'default' | 'error' }> = {
    active: { color: 'bg-emerald-400', variant: 'success' },
    inactive: { color: 'bg-slate-500', variant: 'default' },
    suspended: { color: 'bg-red-400', variant: 'error' },
  };

  return (
    <div className="space-y-6">
      {/* Stats */}
      <div className="grid grid-cols-3 gap-4">
        <StatCard
          icon={Users}
          value={stats.total}
          label="Total Users"
          iconColor="text-blue-400"
          iconBgColor="bg-blue-400/20"
        />
        <StatCard
          icon={Users}
          value={stats.active}
          label="Active"
          iconColor="text-emerald-400"
          iconBgColor="bg-emerald-400/20"
        />
        <StatCard
          icon={Shield}
          value={stats.admins}
          label="Admins"
          iconColor="text-violet-400"
          iconBgColor="bg-violet-400/20"
        />
      </div>

      {error && (
        <div className="p-4 rounded-lg bg-red-500/10 border border-red-500/30 text-red-400">
          {error}
        </div>
      )}

      {authNotConfigured && (
        <Card>
          <CardHeader>
            <CardTitle>Authentication Setup Required</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="space-y-4">
              <p className="text-slate-400">
                User management requires authentication to be configured. Follow these steps to enable it:
              </p>
              <div className="space-y-3 text-sm">
                <div className="p-3 rounded-lg bg-slate-800/50 border border-slate-700">
                  <div className="font-medium text-slate-300 mb-1">1. Set up PostgreSQL</div>
                  <code className="text-xs text-orange-400">brew install postgresql && brew services start postgresql</code>
                </div>
                <div className="p-3 rounded-lg bg-slate-800/50 border border-slate-700">
                  <div className="font-medium text-slate-300 mb-1">2. Create database</div>
                  <code className="text-xs text-orange-400">createdb unamentis</code>
                </div>
                <div className="p-3 rounded-lg bg-slate-800/50 border border-slate-700">
                  <div className="font-medium text-slate-300 mb-1">3. Configure environment variables</div>
                  <div className="space-y-1 mt-2">
                    <code className="block text-xs text-orange-400">export AUTH_SECRET_KEY=&quot;your-secret-key-min-32-chars&quot;</code>
                    <code className="block text-xs text-orange-400">export DATABASE_URL=&quot;postgresql://localhost/unamentis&quot;</code>
                  </div>
                </div>
                <div className="p-3 rounded-lg bg-slate-800/50 border border-slate-700">
                  <div className="font-medium text-slate-300 mb-1">4. Restart the management server</div>
                  <code className="text-xs text-orange-400">python3 server/management/server.py</code>
                </div>
              </div>
            </div>
          </CardContent>
        </Card>
      )}

      {!authNotConfigured && <Card>
        <CardHeader>
          <CardTitle>User Management</CardTitle>
          <div className="flex gap-2">
            <button
              onClick={() => setShowCreateForm(!showCreateForm)}
              className="flex items-center gap-2 px-3 py-1.5 text-sm font-medium rounded-lg bg-orange-500 text-white hover:bg-orange-600 transition-all"
            >
              <Plus className="w-4 h-4" />
              Add User
            </button>
            <button
              onClick={fetchUsers}
              className="flex items-center gap-2 px-3 py-1.5 text-sm font-medium rounded-lg border border-slate-700 text-slate-300 hover:text-slate-100 hover:bg-slate-700/50 transition-all"
            >
              <RefreshCw className="w-4 h-4" />
              Refresh
            </button>
          </div>
        </CardHeader>
        <CardContent>
          {/* Create User Form */}
          {showCreateForm && (
            <form onSubmit={handleCreateUser} className="mb-6 p-4 rounded-lg bg-slate-800/50 border border-slate-700">
              <h3 className="text-lg font-medium mb-4">Create New User</h3>
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="block text-sm font-medium text-slate-400 mb-1">Email</label>
                  <input
                    type="email"
                    required
                    value={formData.email}
                    onChange={(e) => setFormData({ ...formData, email: e.target.value })}
                    className="w-full px-3 py-2 rounded-lg bg-slate-900 border border-slate-700 text-slate-100 focus:outline-none focus:ring-2 focus:ring-orange-500"
                    placeholder="user@example.com"
                  />
                </div>
                <div>
                  <label className="block text-sm font-medium text-slate-400 mb-1">Display Name</label>
                  <input
                    type="text"
                    required
                    value={formData.display_name}
                    onChange={(e) => setFormData({ ...formData, display_name: e.target.value })}
                    className="w-full px-3 py-2 rounded-lg bg-slate-900 border border-slate-700 text-slate-100 focus:outline-none focus:ring-2 focus:ring-orange-500"
                    placeholder="John Doe"
                  />
                </div>
                <div>
                  <label className="block text-sm font-medium text-slate-400 mb-1">Password</label>
                  <input
                    type="password"
                    required
                    minLength={8}
                    value={formData.password}
                    onChange={(e) => setFormData({ ...formData, password: e.target.value })}
                    className="w-full px-3 py-2 rounded-lg bg-slate-900 border border-slate-700 text-slate-100 focus:outline-none focus:ring-2 focus:ring-orange-500"
                    placeholder="Min 8 characters"
                  />
                </div>
                <div>
                  <label className="block text-sm font-medium text-slate-400 mb-1">Role</label>
                  <select
                    value={formData.role}
                    onChange={(e) => setFormData({ ...formData, role: e.target.value as 'admin' | 'user' })}
                    className="w-full px-3 py-2 rounded-lg bg-slate-900 border border-slate-700 text-slate-100 focus:outline-none focus:ring-2 focus:ring-orange-500"
                  >
                    <option value="user">User</option>
                    <option value="admin">Admin</option>
                  </select>
                </div>
              </div>
              <div className="flex justify-end gap-2 mt-4">
                <button
                  type="button"
                  onClick={() => setShowCreateForm(false)}
                  className="px-4 py-2 text-sm font-medium rounded-lg border border-slate-700 text-slate-300 hover:bg-slate-700/50"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={creating}
                  className="px-4 py-2 text-sm font-medium rounded-lg bg-orange-500 text-white hover:bg-orange-600 disabled:opacity-50"
                >
                  {creating ? 'Creating...' : 'Create User'}
                </button>
              </div>
            </form>
          )}

          {/* Users List */}
          {loading ? (
            <div className="text-center text-slate-500 py-12">Loading users...</div>
          ) : users.length === 0 ? (
            <div className="text-center text-slate-500 py-12">
              <Users className="w-16 h-16 mx-auto mb-4 opacity-30" />
              <p className="text-lg font-medium">No users yet</p>
              <p className="text-sm mt-1">Click &quot;Add User&quot; to create the first user</p>
            </div>
          ) : (
            <div className="space-y-3">
              {users.map((user) => {
                const style = statusStyles[user.status] || statusStyles.inactive;

                return (
                  <div
                    key={user.id}
                    className="flex items-center justify-between p-4 rounded-lg bg-slate-800/30 hover:bg-slate-800/50 transition-colors"
                  >
                    <div className="flex items-center gap-4">
                      <div className="w-10 h-10 rounded-full bg-slate-700 flex items-center justify-center">
                        <span className="text-lg font-medium">
                          {user.display_name?.charAt(0).toUpperCase() || user.email.charAt(0).toUpperCase()}
                        </span>
                      </div>
                      <div>
                        <div className="flex items-center gap-2">
                          <span className="font-medium">{user.display_name || user.email}</span>
                          {user.role === 'admin' && (
                            <Badge variant="info" className="text-xs">
                              <Shield className="w-3 h-3 mr-1" />
                              Admin
                            </Badge>
                          )}
                          <Badge variant={style.variant} className="text-xs">
                            {user.status}
                          </Badge>
                        </div>
                        <div className="flex items-center gap-4 mt-1 text-sm text-slate-400">
                          <span className="flex items-center gap-1">
                            <Mail className="w-3 h-3" />
                            {user.email}
                          </span>
                          <span className="flex items-center gap-1">
                            <Calendar className="w-3 h-3" />
                            Joined {formatRelativeTime(user.created_at)}
                          </span>
                          {user.last_login && (
                            <span>Last login: {formatRelativeTime(user.last_login)}</span>
                          )}
                        </div>
                      </div>
                    </div>
                    <button
                      onClick={() => handleDeleteUser(user.id)}
                      className="p-2 rounded-lg text-slate-400 hover:text-red-400 hover:bg-red-500/10 transition-colors"
                      title="Delete user"
                    >
                      <Trash2 className="w-4 h-4" />
                    </button>
                  </div>
                );
              })}
            </div>
          )}
        </CardContent>
      </Card>}
    </div>
  );
}
